// Private V25 diagnostics. This module is compiled only by the
// Arcade-Dogyuun_event_debug revision.
module dogyuun_v25_debug_trace #(
    parameter integer DETAIL_AW = 10,
    parameter integer SUMMARY_AW = 8,
    parameter integer CE_PER_EPOCH = 12500000,
    parameter integer SILENCE_CE = 37500000,
    parameter integer KEY_MASK_STUCK_CE = 50000000,
    parameter integer YM_QUALIFY_WRITES = 256,
    parameter integer HEARTBEAT_BITS = 20,
    parameter integer SHARED_SAMPLE_BITS = 8
) (
    input              clk,
    input              reset_n,
    input              clock_enable,
    input              instruction_done,
    input      [19:0]  debug_pc,
    input      [2:0]   active_bank,
    input      [15:0]  arch_flags,
    input      [15:0]  arch_cx,
    input      [15:0]  arch_ix,
    input              halted,
    input              fault,
    input              timer2_pending,
    input              timer2_irq_request,
    input              irq_entry_pending,
    input      [7:0]   tmic0_reg,
    input      [7:0]   ispr_reg,
    input      [4:0]   escape_state,
    input      [7:0]   escape_opcode,
    input              bus_write_start,
    input      [19:0]  bus_write_addr,
    input      [7:0]   bus_write_data,
    input              bank_commit,
    input      [2:0]   bank_cause,
    input      [2:0]   bank_source,
    input      [2:0]   bank_target,
    input      [15:0]  bank_psw,
    input      [15:0]  bank_ip,
    input              restore_event,
    input      [31:0]  control,
    output reg [127:0] probe
);

localparam integer DETAIL_DEPTH = 1 << DETAIL_AW;
localparam integer SUMMARY_DEPTH = 1 << SUMMARY_AW;

localparam [7:0]
    TRIGGER_FAULT          = 8'd1,
    TRIGGER_HALT           = 8'd2,
    TRIGGER_PC_RANGE       = 8'd3,
    TRIGGER_YM_SILENCE     = 8'd4,
    TRIGGER_CPU_STALL      = 8'd5,
    TRIGGER_TIMER_IF       = 8'd6,
    TRIGGER_SOURCE_PSW     = 8'd7,
    TRIGGER_RETURN_PSW     = 8'd8,
    TRIGGER_KEY_MASK_STUCK = 8'd9,
    TRIGGER_MANUAL         = 8'hf0;

localparam [2:0]
    BANK_CAUSE_TIMER  = 3'd1,
    BANK_CAUSE_RETRBI = 3'd2,
    BANK_CAUSE_BRKCS  = 3'd3;

(* ramstyle = "M10K" *) reg [127:0] detail_mem [0:DETAIL_DEPTH-1];
(* ramstyle = "M10K" *) reg [127:0] summary_mem [0:SUMMARY_DEPTH-1];

reg [127:0] detail_read_data;
reg [127:0] summary_read_data;
reg [127:0] trigger_snapshot;

reg arm_seen;
reg freeze_seen;
reg armed;
reg detail_frozen;
reg summary_frozen;
reg [7:0] trigger_reason;
reg [DETAIL_AW-1:0] trigger_ptr;

reg [DETAIL_AW-1:0] detail_write_ptr;
reg [DETAIL_AW:0] detail_valid_count;
reg [SUMMARY_AW-1:0] summary_write_ptr;
reg [SUMMARY_AW:0] summary_valid_count;

reg [31:0] v25_tick_count;
reg [31:0] epoch_index;
reg [31:0] epoch_ce_count;
reg [31:0] silence_ce_count;
reg [31:0] instruction_silence_count;
reg [HEARTBEAT_BITS-1:0] heartbeat_div;
reg [SHARED_SAMPLE_BITS-1:0] shared_sample_div;

reg [7:0] ym_address;
reg [15:0] last_ym_pair;
reg ym_activity_qualified;
reg [31:0] ym_total_count;
reg [31:0] oki_total_count;
reg [31:0] shared_total_count;
reg [31:0] key_mask_write_count;

reg [31:0] key_mask_last_tick;
reg [31:0] key_mask_prev_tick;
reg [19:0] key_mask_last_pc;
reg [19:0] key_mask_prev_pc;
reg [19:0] key_mask_last_addr;
reg [19:0] key_mask_prev_addr;
reg [7:0] key_mask_last_data;
reg [7:0] key_mask_prev_data;
reg [15:0] key_mask_last_flags;
reg [15:0] key_mask_prev_flags;
reg [2:0] key_mask_last_bank;
reg [2:0] key_mask_prev_bank;
reg [2:0] keyoff_pattern_index;
reg [6:0] keyoff_pattern_repeats;
reg [31:0] keyoff_pattern_start_tick;

reg [15:0] epoch_ym_count;
reg [15:0] epoch_ym_hash;
reg [7:0] epoch_oki_count;
reg [11:0] epoch_shared_count;
reg [19:0] epoch_instruction_count;
reg [2:0] epoch_bank_seen;

wire arm_event = control[0] != arm_seen;
wire manual_freeze_event = control[1] != freeze_seen;
wire [DETAIL_AW-1:0] detail_read_index = control[11:2];
wire [SUMMARY_AW-1:0] summary_read_index = control[19:12];
wire [3:0] probe_page = control[23:20];

wire ym_address_write =
    bus_write_start && bus_write_addr == 20'h00000;
wire ym_data_write =
    bus_write_start && bus_write_addr == 20'h00001;
wire oki_write =
    bus_write_start && bus_write_addr == 20'h00004;
wire shared_write =
    bus_write_start && bus_write_addr[19];
wire shared_sample =
    shared_write && &shared_sample_div;
wire key_mask_site_write =
    bus_write_start &&
    (debug_pc == 20'ha4d9f ||
     debug_pc == 20'ha4e0d ||
     debug_pc == 20'ha4bba);
wire key_mask_write =
    bus_write_start &&
    (bus_write_addr[14:0] == 15'h780d || key_mask_site_write);
wire keyoff_pattern_write =
    ym_data_write && ym_address == 8'h08;
wire heartbeat_event =
    clock_enable && &heartbeat_div;
wire epoch_end =
    armed && clock_enable && epoch_ce_count >= CE_PER_EPOCH - 1;

wire pc_range_fault =
    armed && instruction_done &&
    (debug_pc < 20'ha0000 || debug_pc >= 20'ha8000);
wire timer_if_fault =
    bank_commit && bank_cause == BANK_CAUSE_TIMER && !bank_psw[9];
wire source_psw_fault =
    bank_commit &&
    (bank_cause == BANK_CAUSE_TIMER ||
     bank_cause == BANK_CAUSE_BRKCS) &&
    bank_psw[14:12] != bank_source;
wire return_psw_fault =
    bank_commit && bank_cause == BANK_CAUSE_RETRBI &&
    bank_psw[14:12] != bank_target;
wire ym_silence_fault =
    armed && ym_activity_qualified && clock_enable &&
    silence_ce_count >= SILENCE_CE - 1;
wire cpu_stall_fault =
    armed && ym_activity_qualified && clock_enable &&
    instruction_silence_count >= SILENCE_CE - 1;
wire key_mask_stuck_fault =
    armed && keyoff_pattern_write &&
    keyoff_pattern_index == 3'd7 &&
    keyoff_pattern_repeats != 7'd0 &&
    v25_tick_count - keyoff_pattern_start_tick >= KEY_MASK_STUCK_CE &&
    bus_write_data == 8'h00;

reg auto_trigger;
reg [7:0] auto_trigger_reason;
always @* begin
    auto_trigger = 1'b0;
    auto_trigger_reason = 8'd0;
    if (armed && !detail_frozen && !arm_event) begin
        if (fault) begin
            auto_trigger = 1'b1;
            auto_trigger_reason = TRIGGER_FAULT;
        end else if (halted) begin
            auto_trigger = 1'b1;
            auto_trigger_reason = TRIGGER_HALT;
        end else if (pc_range_fault) begin
            auto_trigger = 1'b1;
            auto_trigger_reason = TRIGGER_PC_RANGE;
        end else if (key_mask_stuck_fault) begin
            auto_trigger = 1'b1;
            auto_trigger_reason = TRIGGER_KEY_MASK_STUCK;
        end else if (ym_silence_fault) begin
            auto_trigger = 1'b1;
            auto_trigger_reason = TRIGGER_YM_SILENCE;
        end else if (cpu_stall_fault) begin
            auto_trigger = 1'b1;
            auto_trigger_reason = TRIGGER_CPU_STALL;
        end else if (timer_if_fault) begin
            auto_trigger = 1'b1;
            auto_trigger_reason = TRIGGER_TIMER_IF;
        end else if (source_psw_fault) begin
            auto_trigger = 1'b1;
            auto_trigger_reason = TRIGGER_SOURCE_PSW;
        end else if (return_psw_fault) begin
            auto_trigger = 1'b1;
            auto_trigger_reason = TRIGGER_RETURN_PSW;
        end
    end
end

reg event_valid;
reg [7:0] event_type;
reg [2:0] event_source_bank;
reg [2:0] event_target_bank;
reg [15:0] event_payload0;
reg [15:0] event_payload1;
reg [127:0] event_word;

always @* begin
    event_valid = 1'b0;
    event_type = 8'd0;
    event_source_bank = active_bank;
    event_target_bank = active_bank;
    event_payload0 = last_ym_pair;
    event_payload1 = {ispr_reg, tmic0_reg};

    if (auto_trigger) begin
        event_valid = 1'b1;
        event_type = 8'he0 | auto_trigger_reason;
        if (auto_trigger_reason == TRIGGER_KEY_MASK_STUCK) begin
            event_payload0 = {ym_address, bus_write_data};
            event_payload1 = {8'h00, key_mask_last_data};
        end else if (auto_trigger_reason >= TRIGGER_TIMER_IF &&
            auto_trigger_reason <= TRIGGER_RETURN_PSW) begin
            event_source_bank = bank_source;
            event_target_bank = bank_target;
            event_payload0 = bank_psw;
            event_payload1 = bank_ip;
        end
    end else if (manual_freeze_event) begin
        event_valid = 1'b1;
        event_type = TRIGGER_MANUAL;
    end else if (key_mask_write) begin
        event_valid = 1'b1;
        event_type = 8'h13;
        event_payload0 = {arch_cx[7:0], bus_write_data};
        event_payload1 = arch_ix;
    end else if (bank_commit && bank_cause == BANK_CAUSE_BRKCS) begin
        event_valid = 1'b1;
        event_type = 8'h20 + {5'd0, bank_cause};
        event_source_bank = bank_source;
        event_target_bank = bank_target;
        event_payload0 = bank_psw;
        event_payload1 = bank_ip;
    end else if (restore_event) begin
        event_valid = 1'b1;
        event_type = 8'h30;
    end else if (ym_data_write) begin
        event_valid = 1'b1;
        event_type = 8'h10;
        event_payload0 = {ym_address, bus_write_data};
    end else if (oki_write) begin
        event_valid = 1'b1;
        event_type = 8'h11;
        event_payload0 = {8'h00, bus_write_data};
    end else if (shared_sample) begin
        event_valid = 1'b1;
        event_type = 8'h12;
        event_payload0 = bus_write_addr[15:0];
        event_payload1 = {
            bus_write_addr[19:16], 4'h0, bus_write_data
        };
    end else if (heartbeat_event) begin
        event_valid = 1'b1;
        event_type = 8'h40;
    end

    event_word = {
        halted,
        fault,
        arch_flags[9],
        irq_entry_pending,
        timer2_irq_request,
        timer2_pending,
        escape_state,
        arch_flags,
        event_payload1,
        event_payload0,
        event_target_bank,
        event_source_bank,
        active_bank,
        debug_pc,
        event_type,
        v25_tick_count
    };
end

wire [127:0] summary_word = {
    detail_frozen,
    halted,
    fault,
    epoch_bank_seen,
    irq_entry_pending,
    timer2_pending,
    arch_flags[9],
    active_bank,
    debug_pc,
    epoch_instruction_count,
    epoch_shared_count,
    epoch_oki_count,
    epoch_ym_hash,
    epoch_ym_count,
    epoch_index[23:0]
};

always @(posedge clk) begin
    detail_read_data <= detail_mem[detail_read_index];
    summary_read_data <= summary_mem[summary_read_index];

    if (!reset_n) begin
        arm_seen <= control[0];
        freeze_seen <= control[1];
        armed <= 1'b0;
        detail_frozen <= 1'b0;
        summary_frozen <= 1'b0;
        trigger_reason <= 8'd0;
        trigger_ptr <= {DETAIL_AW{1'b0}};
        trigger_snapshot <= 128'd0;
        detail_write_ptr <= {DETAIL_AW{1'b0}};
        detail_valid_count <= {(DETAIL_AW + 1){1'b0}};
        summary_write_ptr <= {SUMMARY_AW{1'b0}};
        summary_valid_count <= {(SUMMARY_AW + 1){1'b0}};
        v25_tick_count <= 32'd0;
        epoch_index <= 32'd0;
        epoch_ce_count <= 32'd0;
        silence_ce_count <= 32'd0;
        instruction_silence_count <= 32'd0;
        heartbeat_div <= {HEARTBEAT_BITS{1'b0}};
        shared_sample_div <= {SHARED_SAMPLE_BITS{1'b0}};
        ym_address <= 8'd0;
        last_ym_pair <= 16'd0;
        ym_activity_qualified <= 1'b0;
        ym_total_count <= 32'd0;
        oki_total_count <= 32'd0;
        shared_total_count <= 32'd0;
        key_mask_write_count <= 32'd0;
        key_mask_last_tick <= 32'd0;
        key_mask_prev_tick <= 32'd0;
        key_mask_last_pc <= 20'd0;
        key_mask_prev_pc <= 20'd0;
        key_mask_last_addr <= 20'd0;
        key_mask_prev_addr <= 20'd0;
        key_mask_last_data <= 8'd0;
        key_mask_prev_data <= 8'd0;
        key_mask_last_flags <= 16'd0;
        key_mask_prev_flags <= 16'd0;
        key_mask_last_bank <= 3'd0;
        key_mask_prev_bank <= 3'd0;
        keyoff_pattern_index <= 3'd0;
        keyoff_pattern_repeats <= 7'd0;
        keyoff_pattern_start_tick <= 32'd0;
        epoch_ym_count <= 16'd0;
        epoch_ym_hash <= 16'h1d0f;
        epoch_oki_count <= 8'd0;
        epoch_shared_count <= 12'd0;
        epoch_instruction_count <= 20'd0;
        epoch_bank_seen <= 3'd0;
    end else if (arm_event) begin
        arm_seen <= control[0];
        freeze_seen <= control[1];
        armed <= 1'b1;
        detail_frozen <= 1'b0;
        summary_frozen <= 1'b0;
        trigger_reason <= 8'd0;
        trigger_ptr <= {DETAIL_AW{1'b0}};
        trigger_snapshot <= 128'd0;
        detail_write_ptr <= {DETAIL_AW{1'b0}};
        detail_valid_count <= {(DETAIL_AW + 1){1'b0}};
        summary_write_ptr <= {SUMMARY_AW{1'b0}};
        summary_valid_count <= {(SUMMARY_AW + 1){1'b0}};
        v25_tick_count <= 32'd0;
        epoch_index <= 32'd0;
        epoch_ce_count <= 32'd0;
        silence_ce_count <= 32'd0;
        instruction_silence_count <= 32'd0;
        heartbeat_div <= {HEARTBEAT_BITS{1'b0}};
        shared_sample_div <= {SHARED_SAMPLE_BITS{1'b0}};
        ym_address <= 8'd0;
        last_ym_pair <= 16'd0;
        ym_activity_qualified <= 1'b0;
        ym_total_count <= 32'd0;
        oki_total_count <= 32'd0;
        shared_total_count <= 32'd0;
        key_mask_write_count <= 32'd0;
        key_mask_last_tick <= 32'd0;
        key_mask_prev_tick <= 32'd0;
        key_mask_last_pc <= 20'd0;
        key_mask_prev_pc <= 20'd0;
        key_mask_last_addr <= 20'd0;
        key_mask_prev_addr <= 20'd0;
        key_mask_last_data <= 8'd0;
        key_mask_prev_data <= 8'd0;
        key_mask_last_flags <= 16'd0;
        key_mask_prev_flags <= 16'd0;
        key_mask_last_bank <= 3'd0;
        key_mask_prev_bank <= 3'd0;
        keyoff_pattern_index <= 3'd0;
        keyoff_pattern_repeats <= 7'd0;
        keyoff_pattern_start_tick <= 32'd0;
        epoch_ym_count <= 16'd0;
        epoch_ym_hash <= 16'h1d0f;
        epoch_oki_count <= 8'd0;
        epoch_shared_count <= 12'd0;
        epoch_instruction_count <= 20'd0;
        epoch_bank_seen <= 3'd0;
    end else begin
        if (manual_freeze_event) begin
            freeze_seen <= control[1];
            detail_frozen <= 1'b1;
            summary_frozen <= 1'b1;
            if (!detail_frozen) begin
                trigger_reason <= TRIGGER_MANUAL;
                trigger_ptr <= detail_write_ptr;
                trigger_snapshot <= event_word;
            end
        end

        if (clock_enable) begin
            v25_tick_count <= v25_tick_count + 1'b1;
            heartbeat_div <= heartbeat_div + 1'b1;
            if (armed) begin
                if (epoch_end)
                    epoch_ce_count <= 32'd0;
                else
                    epoch_ce_count <= epoch_ce_count + 1'b1;

                if (ym_activity_qualified && !detail_frozen) begin
                    if (!ym_data_write &&
                        silence_ce_count < SILENCE_CE)
                        silence_ce_count <= silence_ce_count + 1'b1;
                    if (!instruction_done &&
                        instruction_silence_count < SILENCE_CE)
                        instruction_silence_count <=
                            instruction_silence_count + 1'b1;
                end
            end
        end

        if (instruction_done) begin
            instruction_silence_count <= 32'd0;
            if (armed && !summary_frozen &&
                epoch_instruction_count != 20'hfffff)
                epoch_instruction_count <=
                    epoch_instruction_count + 1'b1;
        end

        if (ym_address_write)
            ym_address <= bus_write_data;

        if (ym_data_write) begin
            last_ym_pair <= {ym_address, bus_write_data};
            silence_ce_count <= 32'd0;
            ym_total_count <= ym_total_count + 1'b1;
            if (ym_total_count + 1 >= YM_QUALIFY_WRITES)
                ym_activity_qualified <= 1'b1;
            if (armed && !summary_frozen) begin
                if (epoch_ym_count != 16'hffff)
                    epoch_ym_count <= epoch_ym_count + 1'b1;
                epoch_ym_hash <=
                    {epoch_ym_hash[14:0], epoch_ym_hash[15]} ^
                    {ym_address, bus_write_data} ^ 16'h1d0f;
            end
        end

        if (keyoff_pattern_write) begin
            case (keyoff_pattern_index)
                3'd0: begin
                    if (bus_write_data == 8'h07) begin
                        keyoff_pattern_index <= 3'd1;
                    end else begin
                        keyoff_pattern_index <= 3'd0;
                        keyoff_pattern_repeats <= 7'd0;
                        keyoff_pattern_start_tick <= 32'd0;
                    end
                end
                3'd1: begin
                    keyoff_pattern_index <=
                        bus_write_data == 8'h06 ? 3'd2 : 3'd0;
                    if (bus_write_data != 8'h06)
                        keyoff_pattern_repeats <= 7'd0;
                    if (bus_write_data != 8'h06)
                        keyoff_pattern_start_tick <= 32'd0;
                end
                3'd2: begin
                    keyoff_pattern_index <=
                        bus_write_data == 8'h05 ? 3'd3 : 3'd0;
                    if (bus_write_data != 8'h05)
                        keyoff_pattern_repeats <= 7'd0;
                    if (bus_write_data != 8'h05)
                        keyoff_pattern_start_tick <= 32'd0;
                end
                3'd3: begin
                    keyoff_pattern_index <=
                        bus_write_data == 8'h7c ? 3'd4 : 3'd0;
                    if (bus_write_data != 8'h7c)
                        keyoff_pattern_repeats <= 7'd0;
                    if (bus_write_data != 8'h7c)
                        keyoff_pattern_start_tick <= 32'd0;
                end
                3'd4: begin
                    keyoff_pattern_index <=
                        bus_write_data == 8'h03 ? 3'd5 : 3'd0;
                    if (bus_write_data != 8'h03)
                        keyoff_pattern_repeats <= 7'd0;
                    if (bus_write_data != 8'h03)
                        keyoff_pattern_start_tick <= 32'd0;
                end
                3'd5: begin
                    keyoff_pattern_index <=
                        bus_write_data == 8'h02 ? 3'd6 : 3'd0;
                    if (bus_write_data != 8'h02)
                        keyoff_pattern_repeats <= 7'd0;
                    if (bus_write_data != 8'h02)
                        keyoff_pattern_start_tick <= 32'd0;
                end
                3'd6: begin
                    keyoff_pattern_index <=
                        bus_write_data == 8'h01 ? 3'd7 : 3'd0;
                    if (bus_write_data != 8'h01)
                        keyoff_pattern_repeats <= 7'd0;
                    if (bus_write_data != 8'h01)
                        keyoff_pattern_start_tick <= 32'd0;
                end
                default: begin
                    keyoff_pattern_index <= 3'd0;
                    if (bus_write_data == 8'h00) begin
                        if (keyoff_pattern_repeats == 7'd0)
                            keyoff_pattern_start_tick <= v25_tick_count;
                        if (keyoff_pattern_repeats != 7'd127)
                            keyoff_pattern_repeats <=
                                keyoff_pattern_repeats + 1'b1;
                    end else begin
                        keyoff_pattern_repeats <= 7'd0;
                        keyoff_pattern_start_tick <= 32'd0;
                    end
                end
            endcase
        end

        if (oki_write) begin
            oki_total_count <= oki_total_count + 1'b1;
            if (armed && !summary_frozen &&
                epoch_oki_count != 8'hff)
                epoch_oki_count <= epoch_oki_count + 1'b1;
        end

        if (shared_write) begin
            shared_sample_div <= shared_sample_div + 1'b1;
            shared_total_count <= shared_total_count + 1'b1;
            if (armed && !summary_frozen &&
                epoch_shared_count != 12'hfff)
                epoch_shared_count <= epoch_shared_count + 1'b1;
        end

        if (key_mask_write) begin
            key_mask_write_count <= key_mask_write_count + 1'b1;
            key_mask_prev_tick <= key_mask_last_tick;
            key_mask_prev_pc <= key_mask_last_pc;
            key_mask_prev_addr <= key_mask_last_addr;
            key_mask_prev_data <= key_mask_last_data;
            key_mask_prev_flags <= key_mask_last_flags;
            key_mask_prev_bank <= key_mask_last_bank;
            key_mask_last_tick <= v25_tick_count;
            key_mask_last_pc <= debug_pc;
            key_mask_last_addr <= bus_write_addr;
            key_mask_last_data <= bus_write_data;
            key_mask_last_flags <= arch_flags;
            key_mask_last_bank <= active_bank;
        end

        if (bank_commit && armed && !summary_frozen) begin
            case (bank_cause)
                BANK_CAUSE_TIMER:  epoch_bank_seen[0] <= 1'b1;
                BANK_CAUSE_RETRBI: epoch_bank_seen[1] <= 1'b1;
                BANK_CAUSE_BRKCS:  epoch_bank_seen[2] <= 1'b1;
                default: ;
            endcase
        end

        if (epoch_end) begin
            if (!summary_frozen) begin
                summary_mem[summary_write_ptr] <= summary_word;
                summary_write_ptr <= summary_write_ptr + 1'b1;
                if (summary_valid_count != SUMMARY_DEPTH)
                    summary_valid_count <= summary_valid_count + 1'b1;
            end
            epoch_index <= epoch_index + 1'b1;
            epoch_ym_count <= ym_data_write ? 16'd1 : 16'd0;
            epoch_ym_hash <= ym_data_write ?
                (16'h3a1e ^
                 {ym_address, bus_write_data} ^ 16'h1d0f) :
                16'h1d0f;
            epoch_oki_count <= oki_write ? 8'd1 : 8'd0;
            epoch_shared_count <= shared_write ? 12'd1 : 12'd0;
            epoch_instruction_count <= instruction_done ? 20'd1 : 20'd0;
            epoch_bank_seen <= {
                bank_commit && bank_cause == BANK_CAUSE_BRKCS,
                bank_commit && bank_cause == BANK_CAUSE_RETRBI,
                bank_commit && bank_cause == BANK_CAUSE_TIMER
            };
        end

        if (armed && !detail_frozen && event_valid) begin
            detail_mem[detail_write_ptr] <= event_word;
            detail_write_ptr <= detail_write_ptr + 1'b1;
            if (detail_valid_count != DETAIL_DEPTH)
                detail_valid_count <= detail_valid_count + 1'b1;
            if (auto_trigger || manual_freeze_event) begin
                detail_frozen <= 1'b1;
                trigger_reason <= auto_trigger ?
                    auto_trigger_reason : TRIGGER_MANUAL;
                trigger_ptr <= detail_write_ptr;
                trigger_snapshot <= event_word;
            end
        end
    end
end

always @* begin
    probe = 128'd0;
    case (probe_page)
        4'd0: begin
            probe[DETAIL_AW-1:0] = detail_write_ptr;
            probe[20:10] = detail_valid_count;
            probe[30:21] = trigger_ptr;
            probe[38:31] = trigger_reason;
            probe[39] = armed;
            probe[40] = detail_frozen;
            probe[41] = summary_frozen;
            probe[42] = detail_valid_count[DETAIL_AW];
            probe[50:43] = summary_write_ptr;
            probe[59:51] = summary_valid_count;
            probe[91:60] = v25_tick_count;
            probe[111:92] = debug_pc;
            probe[127:112] = 16'hd250;
        end
        4'd1: probe = trigger_snapshot;
        4'd2: probe = detail_read_data;
        4'd3: probe = summary_read_data;
        4'd4: begin
            probe[19:0] = debug_pc;
            probe[22:20] = active_bank;
            probe[38:23] = arch_flags;
            probe[39] = halted;
            probe[40] = fault;
            probe[41] = timer2_pending;
            probe[42] = timer2_irq_request;
            probe[43] = irq_entry_pending;
            probe[51:44] = tmic0_reg;
            probe[59:52] = ispr_reg;
            probe[64:60] = escape_state;
            probe[72:65] = escape_opcode;
            probe[88:73] = last_ym_pair;
            probe[111:89] = silence_ce_count[22:0];
            probe[127:112] = 16'hd254;
        end
        4'd5: begin
            probe[31:0] = ym_total_count;
            probe[63:32] = oki_total_count;
            probe[95:64] = shared_total_count;
            probe[111:96] = last_ym_pair;
            probe[127:112] = 16'hd255;
        end
        4'd6: begin
            probe[7:0] = DETAIL_AW;
            probe[15:8] = SUMMARY_AW;
            probe[47:16] = CE_PER_EPOCH;
            probe[79:48] = SILENCE_CE;
            probe[95:80] = YM_QUALIFY_WRITES;
            probe[111:96] = 16'd3;
            probe[127:112] = 16'hd256;
        end
        4'd7: begin
            probe[31:0] = key_mask_last_tick;
            probe[51:32] = key_mask_last_pc;
            probe[71:52] = key_mask_last_addr;
            probe[79:72] = key_mask_last_data;
            probe[95:80] = key_mask_last_flags;
            probe[98:96] = key_mask_last_bank;
            probe[101:99] = keyoff_pattern_index;
            probe[108:102] = keyoff_pattern_repeats;
            probe[111:109] = key_mask_write_count[2:0];
            probe[127:112] = 16'hd257;
        end
        4'd8: begin
            probe[31:0] = key_mask_prev_tick;
            probe[51:32] = key_mask_prev_pc;
            probe[71:52] = key_mask_prev_addr;
            probe[79:72] = key_mask_prev_data;
            probe[95:80] = key_mask_prev_flags;
            probe[98:96] = key_mask_prev_bank;
            probe[127:112] = 16'hd258;
        end
        default: probe[127:112] = 16'hd25f;
    endcase
end

endmodule

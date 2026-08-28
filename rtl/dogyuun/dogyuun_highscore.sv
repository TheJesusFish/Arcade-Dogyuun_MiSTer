// SPDX-License-Identifier: GPL-3.0-or-later

// Dogyuun-local high-score persistence. Supported MRAs provide one exact
// MAME hiscore descriptor at index 4 and a 264-byte NVRAM image at index 2.
module dogyuun_highscore (
    input              clk,
    input              reset,
    input              cpu_reset,

    input              config_download,
    input              config_wr,
    input      [26:0]  config_addr,
    input      [7:0]   config_data,

    input              nvram_download,
    input              nvram_upload,
    input              nvram_wr,
    input              nvram_rd,
    input      [26:0]  nvram_addr,
    input      [7:0]   nvram_data,
    output     [7:0]   nvram_q,
    output             nvram_wait,

    input              ss_active,
    input      [12:0]  normal_ram_addr,
    input      [1:0]   normal_ram_we,
    input      [15:0]  normal_ram_data,

    output             hold_request,
    input              hold_ack,
    output             ram_owned,
    output     [12:0]  ram_addr,
    output     [1:0]   ram_we,
    output     [15:0]  ram_data,
    input      [15:0]  ram_q,

    output             dirty,
    output             active,
    output             config_valid
);

localparam [8:0] NVRAM_SIZE       = 9'd264;
localparam [8:0] SCORE_WINDOW_SIZE = 9'd256;
localparam [7:0] SCORE_DATA_SIZE   = 8'd124;
localparam [15:0] SCORE_FIRST      = 16'h034a;
localparam [15:0] SCORE_LAST       = 16'h03c5;

localparam [3:0] ST_IDLE                 = 4'd0;
localparam [3:0] ST_RESTORE_HOLD         = 4'd1;
localparam [3:0] ST_RESTORE_BUFFER_READ  = 4'd2;
localparam [3:0] ST_RESTORE_RAM_WRITE    = 4'd3;
localparam [3:0] ST_CAPTURE_HOLD         = 4'd4;
localparam [3:0] ST_CAPTURE_RAM_READ     = 4'd5;
localparam [3:0] ST_CAPTURE_BUFFER_WRITE = 4'd6;

function automatic [7:0] fixed_config_byte;
    input [2:0] address;
    begin
        case (address)
            3'd0: fixed_config_byte = 8'h00;
            3'd1: fixed_config_byte = 8'h10;
            3'd2: fixed_config_byte = 8'h03;
            3'd3: fixed_config_byte = 8'h4a;
            3'd4: fixed_config_byte = 8'h00;
            3'd5: fixed_config_byte = 8'h7c;
            default: fixed_config_byte = 8'h1b;
        endcase
    end
endfunction

function automatic [7:0] expected_trailer_byte;
    input [2:0] address;
    begin
        case (address)
            3'd0: expected_trailer_byte = 8'h44; // D
            3'd1: expected_trailer_byte = 8'h47; // G
            3'd2: expected_trailer_byte = 8'h48; // H
            3'd3: expected_trailer_byte = 8'h53; // S
            3'd4: expected_trailer_byte = 8'h01; // schema
            3'd5: expected_trailer_byte = 8'h08; // trailer bytes
            3'd6: expected_trailer_byte = 8'h00;
            default: expected_trailer_byte = 8'h7c; // 124 payload bytes
        endcase
    end
endfunction

function automatic [15:0] score_byte_address;
    input [7:0] offset;
    begin
        score_byte_address = SCORE_FIRST + {8'd0, offset};
    end
endfunction

function automatic score_byte_selected;
    input [15:0] address;
    begin
        score_byte_selected = (address >= SCORE_FIRST) &&
                              (address <= SCORE_LAST);
    end
endfunction

function automatic [7:0] select_ram_byte;
    input [15:0] word_data;
    input        byte_lane;
    begin
        select_ram_byte = byte_lane ? word_data[7:0] : word_data[15:8];
    end
endfunction

reg       config_download_d = 1'b0;
reg [3:0] config_count = 4'd0;
reg       config_error = 1'b0;
reg       config_profile_candidate = 1'b0;
reg       config_profile = 1'b0;
reg       config_valid_r = 1'b0;

reg       nvram_download_d = 1'b0;
reg [8:0] nvram_count = 9'd0;
reg       nvram_error = 1'b0;
reg       nvram_valid = 1'b0;

wire load_buffer_wr = nvram_download && nvram_wr &&
                      (nvram_addr < SCORE_WINDOW_SIZE);
wire [7:0] load_buffer_hps_q;
wire [7:0] load_buffer_cpu_q;
wire [7:0] snapshot_buffer_hps_q;

reg [3:0] state = ST_IDLE;
reg [7:0] score_offset = 8'd0;
reg       first_zero_seen = 1'b0;
reg       first_one_seen = 1'b0;
reg       last_seen = 1'b0;
reg       scores_ready = 1'b0;
reg       restore_applied = 1'b0;
reg       dirty_r = 1'b0;
reg       snapshot_valid = 1'b0;
reg       fallback_valid = 1'b0;

reg       nvram_upload_d = 1'b0;
reg       upload_started = 1'b0;
reg       capture_ready = 1'b0;
reg [8:0] upload_read_count = 9'd0;
reg       upload_read_error = 1'b0;
reg       upload_post_capture_write = 1'b0;

wire [15:0] current_score_byte_address = score_byte_address(score_offset);
wire [15:0] normal_even_byte_address = {normal_ram_addr, 1'b0};
wire [15:0] normal_odd_byte_address = {normal_ram_addr, 1'b1};
wire normal_score_write =
    (normal_ram_we[1] && score_byte_selected(normal_even_byte_address)) ||
    (normal_ram_we[0] && score_byte_selected(normal_odd_byte_address));
wire selected_sentinels_seen = last_seen &&
                               (config_profile ? first_one_seen :
                                                 first_zero_seen);

wire snapshot_buffer_wr = state == ST_CAPTURE_BUFFER_WRITE;
wire [7:0] capture_byte = select_ram_byte(
    ram_q, current_score_byte_address[0]
);

jtframe_dual_ram #(.DW(8), .AW(8)) u_load_buffer (
    .clk0  ( clk                    ),
    .data0 ( nvram_data             ),
    .addr0 ( nvram_addr[7:0]        ),
    .we0   ( load_buffer_wr         ),
    .q0    ( load_buffer_hps_q      ),
    .clk1  ( clk                    ),
    .data1 ( 8'd0                   ),
    .addr1 ( score_offset           ),
    .we1   ( 1'b0                   ),
    .q1    ( load_buffer_cpu_q      )
);

jtframe_dual_ram #(.DW(8), .AW(8)) u_snapshot_buffer (
    .clk0  ( clk                    ),
    .data0 ( 8'd0                   ),
    .addr0 ( nvram_addr[7:0]        ),
    .we0   ( 1'b0                   ),
    .q0    ( snapshot_buffer_hps_q  ),
    .clk1  ( clk                    ),
    .data1 ( capture_byte           ),
    .addr1 ( score_offset           ),
    .we1   ( snapshot_buffer_wr     ),
    .q1    (                        )
);

always @(posedge clk) begin
    config_download_d <= config_download;
    nvram_download_d <= nvram_download;

    if (reset) begin
        config_download_d <= 1'b0;
        config_count <= 4'd0;
        config_error <= 1'b0;
        config_profile_candidate <= 1'b0;
        config_profile <= 1'b0;
        config_valid_r <= 1'b0;
        nvram_download_d <= 1'b0;
        nvram_count <= 9'd0;
        nvram_error <= 1'b0;
        nvram_valid <= 1'b0;
    end else begin
        if (config_download && !config_download_d) begin
            config_count <= 4'd0;
            config_error <= 1'b0;
            config_profile_candidate <= 1'b0;
            config_valid_r <= 1'b0;
        end

        if (config_download && config_wr) begin
            if ((config_addr == {23'd0, config_count}) &&
                (config_count < 4'd8)) begin
                if (config_count == 4'd6) begin
                    if ((config_data == 8'h00) ||
                        (config_data == 8'h01)) begin
                        config_profile_candidate <= config_data[0];
                        config_count <= config_count + 4'd1;
                    end else begin
                        config_error <= 1'b1;
                    end
                end else if (config_data ==
                             fixed_config_byte(config_count[2:0])) begin
                    config_count <= config_count + 4'd1;
                end else begin
                    config_error <= 1'b1;
                end
            end else begin
                config_error <= 1'b1;
            end
        end

        if (!config_download && config_download_d) begin
            config_valid_r <= !config_error && (config_count == 4'd8);
            if (!config_error && (config_count == 4'd8))
                config_profile <= config_profile_candidate;
        end

        if (nvram_download && !nvram_download_d) begin
            nvram_count <= 9'd0;
            nvram_error <= 1'b0;
            nvram_valid <= 1'b0;
        end

        if (nvram_download && nvram_wr) begin
            if ((nvram_addr == {18'd0, nvram_count}) &&
                (nvram_count < NVRAM_SIZE)) begin
                nvram_count <= nvram_count + 9'd1;
                if ((nvram_count >= SCORE_DATA_SIZE) &&
                    (nvram_count < SCORE_WINDOW_SIZE) &&
                    (nvram_data != 8'h00))
                    nvram_error <= 1'b1;
                if ((nvram_count >= SCORE_WINDOW_SIZE) &&
                    (nvram_data !=
                     expected_trailer_byte(nvram_count[2:0])))
                    nvram_error <= 1'b1;
            end else begin
                nvram_error <= 1'b1;
            end
        end

        if (!nvram_download && nvram_download_d)
            nvram_valid <= config_valid_r && !nvram_error &&
                           (nvram_count == NVRAM_SIZE);
    end
end

always @(posedge clk) begin
    nvram_upload_d <= nvram_upload;

    if (reset || cpu_reset) begin
        state <= ST_IDLE;
        score_offset <= 8'd0;
        first_zero_seen <= 1'b0;
        first_one_seen <= 1'b0;
        last_seen <= 1'b0;
        scores_ready <= 1'b0;
        restore_applied <= 1'b0;
        dirty_r <= 1'b0;
        snapshot_valid <= 1'b0;
        fallback_valid <= 1'b0;
        nvram_upload_d <= 1'b0;
        upload_started <= 1'b0;
        capture_ready <= 1'b0;
        upload_read_count <= 9'd0;
        upload_read_error <= 1'b0;
        upload_post_capture_write <= 1'b0;
    end else begin
        if ((config_download_d && !config_download) ||
            (nvram_download_d && !nvram_download)) begin
            state <= ST_IDLE;
            restore_applied <= 1'b0;
            dirty_r <= 1'b0;
            snapshot_valid <= 1'b0;
            fallback_valid <= 1'b0;
        end

        // The descriptor endpoints are initialization sentinels, not stable
        // table contents. Observe and permanently latch their exact CPU writes
        // even when those writes precede descriptor delivery.
        if (normal_ram_we[1] &&
            (normal_even_byte_address == SCORE_FIRST)) begin
            if (normal_ram_data[15:8] == 8'h00)
                first_zero_seen <= 1'b1;
            if (normal_ram_data[15:8] == 8'h01)
                first_one_seen <= 1'b1;
        end
        if (normal_ram_we[0] &&
            (normal_odd_byte_address == SCORE_LAST) &&
            (normal_ram_data[7:0] == 8'h1b))
            last_seen <= 1'b1;

        if (config_valid_r && selected_sentinels_seen)
            scores_ready <= 1'b1;

        if (scores_ready && (restore_applied || !nvram_valid) &&
            normal_score_write)
            dirty_r <= 1'b1;

        if (nvram_upload && !nvram_upload_d) begin
            upload_started <= 1'b1;
            capture_ready <= !config_valid_r || !scores_ready;
            snapshot_valid <= 1'b0;
            fallback_valid <= config_valid_r && !scores_ready && nvram_valid;
            upload_read_count <= 9'd0;
            upload_read_error <= 1'b0;
            upload_post_capture_write <= 1'b0;
        end

        if (upload_started && snapshot_valid && normal_score_write)
            upload_post_capture_write <= 1'b1;

        if (nvram_upload && nvram_rd) begin
            if ((upload_read_count < NVRAM_SIZE) &&
                (nvram_addr == {18'd0, upload_read_count}))
                upload_read_count <= upload_read_count + 9'd1;
            else
                upload_read_error <= 1'b1;
        end

        if (!nvram_upload && nvram_upload_d) begin
            if (capture_ready && snapshot_valid && !upload_read_error &&
                !upload_post_capture_write && !normal_score_write &&
                (upload_read_count == NVRAM_SIZE))
                dirty_r <= 1'b0;
            upload_started <= 1'b0;
            capture_ready <= 1'b0;
            snapshot_valid <= 1'b0;
            fallback_valid <= 1'b0;
            upload_read_count <= 9'd0;
            upload_read_error <= 1'b0;
            upload_post_capture_write <= 1'b0;
        end

        if (ss_active && (state != ST_IDLE)) begin
            state <= ST_IDLE;
            score_offset <= 8'd0;
            snapshot_valid <= 1'b0;
            capture_ready <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (config_valid_r && nvram_valid && scores_ready &&
                        !restore_applied && !ss_active) begin
                        state <= ST_RESTORE_HOLD;
                    end else if (upload_started && !capture_ready &&
                                 config_valid_r && scores_ready &&
                                 !ss_active) begin
                        state <= ST_CAPTURE_HOLD;
                    end
                end

                ST_RESTORE_HOLD: begin
                    if (hold_ack) begin
                        score_offset <= 8'd0;
                        state <= ST_RESTORE_BUFFER_READ;
                    end
                end

                ST_RESTORE_BUFFER_READ:
                    state <= ST_RESTORE_RAM_WRITE;

                ST_RESTORE_RAM_WRITE: begin
                    if (score_offset == SCORE_DATA_SIZE - 8'd1) begin
                        restore_applied <= 1'b1;
                        dirty_r <= 1'b0;
                        state <= ST_IDLE;
                    end else begin
                        score_offset <= score_offset + 8'd1;
                        state <= ST_RESTORE_BUFFER_READ;
                    end
                end

                ST_CAPTURE_HOLD: begin
                    if (hold_ack) begin
                        score_offset <= 8'd0;
                        state <= ST_CAPTURE_RAM_READ;
                    end
                end

                ST_CAPTURE_RAM_READ:
                    state <= ST_CAPTURE_BUFFER_WRITE;

                ST_CAPTURE_BUFFER_WRITE: begin
                    if (score_offset == SCORE_DATA_SIZE - 8'd1) begin
                        snapshot_valid <= 1'b1;
                        capture_ready <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        score_offset <= score_offset + 8'd1;
                        state <= ST_CAPTURE_RAM_READ;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
end

assign hold_request = !ss_active &&
                      ((state == ST_RESTORE_HOLD) ||
                       (state == ST_RESTORE_BUFFER_READ) ||
                       (state == ST_RESTORE_RAM_WRITE) ||
                       (state == ST_CAPTURE_HOLD) ||
                       (state == ST_CAPTURE_RAM_READ) ||
                       (state == ST_CAPTURE_BUFFER_WRITE));
assign ram_owned = !ss_active &&
                   ((state == ST_RESTORE_BUFFER_READ) ||
                    (state == ST_RESTORE_RAM_WRITE) ||
                    (state == ST_CAPTURE_RAM_READ) ||
                    (state == ST_CAPTURE_BUFFER_WRITE));

assign ram_addr = current_score_byte_address[13:1];
assign ram_we = (state == ST_RESTORE_RAM_WRITE) && !ss_active ?
                (current_score_byte_address[0] ? 2'b01 : 2'b10) : 2'b00;
assign ram_data = current_score_byte_address[0] ?
                  {8'd0, load_buffer_cpu_q} :
                  {load_buffer_cpu_q, 8'd0};

wire nvram_score_address = nvram_addr < SCORE_DATA_SIZE;
wire nvram_padding_address = (nvram_addr >= SCORE_DATA_SIZE) &&
                             (nvram_addr < SCORE_WINDOW_SIZE);
wire nvram_trailer_address = (nvram_addr >= SCORE_WINDOW_SIZE) &&
                             (nvram_addr < NVRAM_SIZE);
wire upload_image_valid = snapshot_valid || fallback_valid;
wire [7:0] upload_score_q = snapshot_valid ? snapshot_buffer_hps_q :
                                               load_buffer_hps_q;

assign nvram_q = !upload_image_valid ? 8'h00 :
                 nvram_score_address ? upload_score_q :
                 nvram_padding_address ? 8'h00 :
                 nvram_trailer_address ?
                    expected_trailer_byte(nvram_addr[2:0]) : 8'h00;
// Reset or malformed metadata cannot strand a previously started HPS upload.
assign nvram_wait = nvram_upload && upload_started && config_valid_r &&
                    scores_ready && !capture_ready;
assign dirty = dirty_r;
assign active = hold_request || (upload_started && !capture_ready);
assign config_valid = config_valid_r;

endmodule

`timescale 1ns/1ps

module DogyuunHighScoreManager_tb;

reg clk = 1'b0;
always #5 clk = ~clk;

reg reset = 1'b1;
reg cpu_reset = 1'b1;
reg config_download = 1'b0;
reg config_wr = 1'b0;
reg [26:0] config_addr = 27'd0;
reg [7:0] config_data = 8'd0;
reg nvram_download = 1'b0;
reg nvram_upload = 1'b0;
reg nvram_wr = 1'b0;
reg nvram_rd = 1'b0;
reg [26:0] nvram_addr = 27'd0;
reg [7:0] nvram_data = 8'd0;
wire [7:0] nvram_q;
wire nvram_wait;
reg ss_active = 1'b0;
reg [12:0] normal_ram_addr = 13'd0;
reg [1:0] normal_ram_we = 2'b00;
reg [15:0] normal_ram_data = 16'd0;
wire hold_request;
reg hold_ack = 1'b0;
wire ram_owned;
wire [12:0] ram_addr;
wire [1:0] ram_we;
wire [15:0] ram_data;
reg [15:0] ram_q = 16'd0;
wire dirty;
wire active;
wire config_valid;

reg simulated_cpu_busy = 1'b0;
reg [15:0] work_ram [0:8191];
reg [7:0] downloaded_payload [0:123];
reg [7:0] expected_upload [0:263];
integer checks = 0;
integer errors = 0;
integer i;
integer cycles;

dogyuun_highscore dut (
    .clk(clk),
    .reset(reset),
    .cpu_reset(cpu_reset),
    .config_download(config_download),
    .config_wr(config_wr),
    .config_addr(config_addr),
    .config_data(config_data),
    .nvram_download(nvram_download),
    .nvram_upload(nvram_upload),
    .nvram_wr(nvram_wr),
    .nvram_rd(nvram_rd),
    .nvram_addr(nvram_addr),
    .nvram_data(nvram_data),
    .nvram_q(nvram_q),
    .nvram_wait(nvram_wait),
    .ss_active(ss_active),
    .normal_ram_addr(normal_ram_addr),
    .normal_ram_we(normal_ram_we),
    .normal_ram_data(normal_ram_data),
    .hold_request(hold_request),
    .hold_ack(hold_ack),
    .ram_owned(ram_owned),
    .ram_addr(ram_addr),
    .ram_we(ram_we),
    .ram_data(ram_data),
    .ram_q(ram_q),
    .dirty(dirty),
    .active(active),
    .config_valid(config_valid)
);

always @(posedge clk) begin
    if (reset || cpu_reset || !hold_request || ss_active)
        hold_ack <= 1'b0;
    else if (!simulated_cpu_busy)
        hold_ack <= 1'b1;

    ram_q <= work_ram[ram_addr];

    if (normal_ram_we[1])
        work_ram[normal_ram_addr][15:8] <= normal_ram_data[15:8];
    if (normal_ram_we[0])
        work_ram[normal_ram_addr][7:0] <= normal_ram_data[7:0];

    if (ram_we[1])
        work_ram[ram_addr][15:8] <= ram_data[15:8];
    if (ram_we[0])
        work_ram[ram_addr][7:0] <= ram_data[7:0];

    if (ram_owned && !hold_ack) begin
        errors = errors + 1;
        $display("FAIL: RAM ownership without acknowledged CPU hold");
    end
    if (ss_active && (ram_owned || (ram_we != 2'b00))) begin
        errors = errors + 1;
        $display("FAIL: high-score RAM access while save state owns port");
    end
end

function [7:0] descriptor_byte;
    input integer address;
    input integer profile;
    begin
        case (address)
            0: descriptor_byte = 8'h00;
            1: descriptor_byte = 8'h10;
            2: descriptor_byte = 8'h03;
            3: descriptor_byte = 8'h4a;
            4: descriptor_byte = 8'h00;
            5: descriptor_byte = 8'h7c;
            6: descriptor_byte = profile ? 8'h01 : 8'h00;
            default: descriptor_byte = 8'h1b;
        endcase
    end
endfunction

function [7:0] trailer_byte;
    input integer address;
    begin
        case (address)
            0: trailer_byte = 8'h44;
            1: trailer_byte = 8'h47;
            2: trailer_byte = 8'h48;
            3: trailer_byte = 8'h53;
            4: trailer_byte = 8'h01;
            5: trailer_byte = 8'h08;
            6: trailer_byte = 8'h00;
            default: trailer_byte = 8'h7c;
        endcase
    end
endfunction

function [7:0] payload_byte;
    input integer address;
    input integer seed;
    begin
        payload_byte = (address * 37 + seed) & 8'hff;
    end
endfunction

function [7:0] work_byte;
    input integer address;
    begin
        if (address[0])
            work_byte = work_ram[address >> 1][7:0];
        else
            work_byte = work_ram[address >> 1][15:8];
    end
endfunction

task check;
    input condition;
    input [1023:0] message;
    begin
        checks = checks + 1;
        if (!condition) begin
            errors = errors + 1;
            $display("FAIL: %0s", message);
        end
    end
endtask

task clear_work_ram;
    begin
        for (i = 0; i < 8192; i = i + 1)
            work_ram[i] = 16'hcafe;
    end
endtask

task reset_dut;
    begin
        @(negedge clk);
        reset = 1'b1;
        cpu_reset = 1'b1;
        config_download = 1'b0;
        config_wr = 1'b0;
        nvram_download = 1'b0;
        nvram_upload = 1'b0;
        nvram_wr = 1'b0;
        nvram_rd = 1'b0;
        nvram_addr = 27'd0;
        normal_ram_we = 2'b00;
        normal_ram_data = 16'd0;
        ss_active = 1'b0;
        simulated_cpu_busy = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        cpu_reset = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

// corrupt_mode: 0=valid, 1=unknown profile, 2=fixed byte, 3=short.
task send_descriptor;
    input integer profile;
    input integer corrupt_mode;
    integer count;
    reg [7:0] value;
    begin
        count = (corrupt_mode == 3) ? 7 : 8;
        @(negedge clk);
        config_download = 1'b1;
        config_wr = 1'b0;
        for (i = 0; i < count; i = i + 1) begin
            @(negedge clk);
            config_addr = i;
            value = descriptor_byte(i, profile);
            if ((corrupt_mode == 1) && (i == 6))
                value = 8'h02;
            if ((corrupt_mode == 2) && (i == 3))
                value = 8'h4b;
            config_data = value;
            config_wr = 1'b1;
            @(posedge clk);
        end
        @(negedge clk);
        config_wr = 1'b0;
        config_download = 1'b0;
        @(posedge clk);
        @(negedge clk);
    end
endtask

// corrupt_mode: 0=valid, 1=trailer, 2=padding, 3=short.
task download_nvram_image;
    input integer seed;
    input integer corrupt_mode;
    integer count;
    reg [7:0] value;
    begin
        count = (corrupt_mode == 3) ? 263 : 264;
        for (i = 0; i < 124; i = i + 1)
            downloaded_payload[i] = payload_byte(i, seed);
        @(negedge clk);
        nvram_download = 1'b1;
        nvram_wr = 1'b0;
        for (i = 0; i < count; i = i + 1) begin
            if (i < 124)
                value = downloaded_payload[i];
            else if (i < 256)
                value = 8'h00;
            else
                value = trailer_byte(i - 256);
            if ((corrupt_mode == 1) && (i == 259))
                value = 8'h52;
            if ((corrupt_mode == 2) && (i == 200))
                value = 8'h80;
            @(negedge clk);
            nvram_addr = i;
            nvram_data = value;
            nvram_wr = 1'b1;
            @(posedge clk);
        end
        @(negedge clk);
        nvram_wr = 1'b0;
        nvram_download = 1'b0;
        @(posedge clk);
        @(negedge clk);
    end
endtask

task write_normal_byte;
    input integer address;
    input [7:0] value;
    begin
        @(negedge clk);
        normal_ram_addr = address >> 1;
        if (address[0]) begin
            normal_ram_we = 2'b01;
            normal_ram_data = {8'h00, value};
        end else begin
            normal_ram_we = 2'b10;
            normal_ram_data = {value, 8'h00};
        end
        @(posedge clk);
        @(negedge clk);
        normal_ram_we = 2'b00;
        normal_ram_data = 16'd0;
        @(posedge clk);
    end
endtask

task wait_for_hold;
    input integer limit;
    begin
        cycles = 0;
        while (!hold_request && (cycles < limit)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        check(hold_request, "timed out waiting for CPU hold request");
    end
endtask

task wait_for_hold_release;
    input integer limit;
    begin
        cycles = 0;
        while (hold_request && (cycles < limit)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        check(!hold_request, "timed out waiting for CPU hold release");
    end
endtask

task start_upload;
    begin
        @(negedge clk);
        nvram_addr = 27'd0;
        nvram_rd = 1'b0;
        nvram_upload = 1'b1;
        @(posedge clk);
    end
endtask

task wait_for_upload_ready;
    input integer limit;
    begin
        // Observe combinational wait after the upload-start edge has updated
        // upload_started/capture_ready through nonblocking assignments.
        @(negedge clk);
        cycles = 0;
        while (nvram_wait && (cycles < limit)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        check(!nvram_wait, "timed out waiting for coherent upload snapshot");
    end
endtask

task read_upload_byte;
    input integer address;
    input [7:0] expected;
    begin
        @(negedge clk);
        nvram_addr = address;
        nvram_rd = 1'b0;
        @(posedge clk);
        @(negedge clk);
        checks = checks + 1;
        if (nvram_q !== expected) begin
            errors = errors + 1;
            $display("FAIL: uploaded byte %0d got %02x expected %02x",
                     address, nvram_q, expected);
        end
        nvram_rd = 1'b1;
        @(posedge clk);
        @(negedge clk);
        nvram_rd = 1'b0;
    end
endtask

task end_upload;
    begin
        @(negedge clk);
        nvram_rd = 1'b0;
        nvram_upload = 1'b0;
        @(posedge clk);
        @(negedge clk);
        repeat (2) @(posedge clk);
    end
endtask

task build_expected_from_work_ram;
    begin
        for (i = 0; i < 124; i = i + 1)
            expected_upload[i] = work_byte(16'h034a + i);
        for (i = 124; i < 256; i = i + 1)
            expected_upload[i] = 8'h00;
        for (i = 256; i < 264; i = i + 1)
            expected_upload[i] = trailer_byte(i - 256);
    end
endtask

task build_expected_from_download;
    begin
        for (i = 0; i < 124; i = i + 1)
            expected_upload[i] = downloaded_payload[i];
        for (i = 124; i < 256; i = i + 1)
            expected_upload[i] = 8'h00;
        for (i = 256; i < 264; i = i + 1)
            expected_upload[i] = trailer_byte(i - 256);
    end
endtask

task read_complete_upload;
    begin
        for (i = 0; i < 264; i = i + 1)
            read_upload_byte(i, expected_upload[i]);
    end
endtask

task check_restored_payload;
    begin
        for (i = 0; i < 124; i = i + 1)
            check(work_byte(16'h034a + i) === downloaded_payload[i],
                  "restored payload byte mismatch");
    end
endtask

initial begin
    clear_work_ram();

    // Descriptor validation fails closed for unknown, malformed, and short
    // metadata. An unsupported personality cannot request RAM or stall HPS.
    reset_dut();
    send_descriptor(0, 1);
    check(!config_valid, "unknown descriptor profile accepted");
    start_upload();
    repeat (2) @(posedge clk);
    check(!nvram_wait && !hold_request && !active,
          "unsupported descriptor did not stay inert");
    read_upload_byte(0, 8'h00);
    end_upload();

    reset_dut();
    send_descriptor(0, 2);
    check(!config_valid, "malformed descriptor accepted");
    reset_dut();
    send_descriptor(0, 3);
    check(!config_valid, "short descriptor accepted");

    // Strict NVRAM validation rejects trailer, padding, and length errors.
    reset_dut();
    send_descriptor(0, 0);
    write_normal_byte(16'h034a, 8'h00);
    write_normal_byte(16'h03c5, 8'h1b);
    download_nvram_image(8'h11, 1);
    repeat (20) @(posedge clk);
    check(!hold_request, "bad NVRAM trailer initiated restore");

    reset_dut();
    send_descriptor(0, 0);
    write_normal_byte(16'h034a, 8'h00);
    write_normal_byte(16'h03c5, 8'h1b);
    download_nvram_image(8'h12, 2);
    repeat (20) @(posedge clk);
    check(!hold_request, "nonzero NVRAM padding initiated restore");

    reset_dut();
    send_descriptor(0, 0);
    write_normal_byte(16'h034a, 8'h00);
    write_normal_byte(16'h03c5, 8'h1b);
    download_nvram_image(8'h13, 3);
    repeat (20) @(posedge clk);
    check(!hold_request, "short NVRAM initiated restore");

    // Profile 0: readiness writes precede descriptor delivery. Hold waits for
    // an active transaction to drain, and save-state ownership aborts a
    // partial restore before the manager retries the complete payload.
    reset_dut();
    clear_work_ram();
    write_normal_byte(16'h0349, 8'h5a);
    write_normal_byte(16'h03c6, 8'ha5);
    write_normal_byte(16'h034a, 8'h00);
    write_normal_byte(16'h03c5, 8'h1b);
    send_descriptor(0, 0);
    check(config_valid, "profile 0 descriptor rejected");
    simulated_cpu_busy = 1'b1;
    download_nvram_image(8'h20, 0);
    wait_for_hold(50);
    repeat (4) @(posedge clk);
    check(!hold_ack && !ram_owned,
          "manager owned RAM before active CPU transaction drained");
    simulated_cpu_busy = 1'b0;
    cycles = 0;
    while (!ram_owned && (cycles < 30)) begin
        @(posedge clk);
        cycles = cycles + 1;
    end
    check(ram_owned, "restore never acquired RAM after CPU drain");
    @(negedge clk);
    ss_active = 1'b1;
    @(posedge clk);
    @(negedge clk);
    check(!hold_request && !ram_owned && (ram_we == 2'b00),
          "save-state priority did not quiesce high-score RAM client");
    ss_active = 1'b0;
    wait_for_hold(40);
    wait_for_hold_release(700);
    repeat (3) @(posedge clk);
    check_restored_payload();
    check(work_byte(16'h0349) == 8'h5a,
          "restore wrote below score range");
    check(work_byte(16'h03c6) == 8'ha5,
          "restore wrote above score range");
    check(!dirty, "initial restore marked scores dirty");

    // Dirty tracking uses ordinary writes only and both 68000 byte lanes.
    write_normal_byte(16'h0349, 8'h6a);
    check(!dirty, "out-of-range write marked scores dirty");
    write_normal_byte(16'h034c, 8'he1);
    check(dirty, "upper-lane score write did not mark dirty");

    // An interrupted upload retains dirty state.
    build_expected_from_work_ram();
    start_upload();
    wait_for_upload_ready(700);
    for (i = 0; i < 17; i = i + 1)
        read_upload_byte(i, expected_upload[i]);
    end_upload();
    check(dirty, "interrupted upload cleared dirty state");

    // Capture is coherent: CPU writes after the snapshot do not alter the
    // uploaded image and must leave the newer RAM contents dirty.
    build_expected_from_work_ram();
    start_upload();
    wait_for_upload_ready(700);
    write_normal_byte(16'h034f, 8'h55);
    read_complete_upload();
    end_upload();
    check(dirty, "post-capture CPU write was lost at upload completion");

    // A complete, unmodified 264-byte transfer clears dirty. Every payload,
    // padding, and Dogyuun trailer byte is checked by read_complete_upload.
    build_expected_from_work_ram();
    start_upload();
    wait_for_upload_ready(700);
    read_complete_upload();
    end_upload();
    check(!dirty, "complete coherent upload did not clear dirty");
    write_normal_byte(16'h034d, 8'h77);
    check(dirty, "lower-lane score write did not mark dirty");

    // Reset during a stalled capture must release both CPU hold and HPS wait.
    simulated_cpu_busy = 1'b1;
    start_upload();
    wait_for_hold(40);
    check(nvram_wait, "capture did not backpressure HPS while CPU was busy");
    @(negedge clk);
    cpu_reset = 1'b1;
    @(posedge clk);
    @(negedge clk);
    check(!nvram_wait && !hold_request,
          "CPU reset left high-score upload or hold stranded");
    nvram_upload = 1'b0;
    simulated_cpu_busy = 1'b0;
    @(posedge clk);
    @(negedge clk);
    cpu_reset = 1'b0;
    repeat (3) @(posedge clk);

    // Profile 1: valid NVRAM can be returned byte-for-byte before readiness,
    // avoiding an early manual-save deadlock. Readiness then requires the
    // profile-specific 0x01 upper-lane write after descriptor delivery.
    reset_dut();
    clear_work_ram();
    send_descriptor(1, 0);
    check(config_valid, "profile 1 descriptor rejected");
    download_nvram_image(8'h70, 0);
    build_expected_from_download();
    start_upload();
    repeat (3) @(posedge clk);
    check(!nvram_wait && !hold_request,
          "early manual upload deadlocked before readiness");
    read_complete_upload();
    end_upload();
    write_normal_byte(16'h034a, 8'h00);
    write_normal_byte(16'h03c5, 8'h1b);
    repeat (20) @(posedge clk);
    check(!hold_request,
          "profile 1 accepted profile 0 first sentinel");
    write_normal_byte(16'h034a, 8'h01);
    wait_for_hold(40);
    wait_for_hold_release(700);
    repeat (3) @(posedge clk);
    check_restored_payload();
    check(!dirty, "profile 1 restore marked scores dirty");

    // With no descriptor at all, the excluded Z80/bootleg personalities stay
    // inert and an upload completes as an invalid all-zero image.
    reset_dut();
    start_upload();
    repeat (2) @(posedge clk);
    check(!nvram_wait && !hold_request && !active,
          "missing descriptor did not stay inert");
    read_upload_byte(0, 8'h00);
    read_upload_byte(256, 8'h00);
    end_upload();

    if (errors == 0) begin
        $display("PASS: Dogyuun high-score manager (%0d checks)", checks);
        $finish;
    end

    $fatal(1, "FAIL: Dogyuun high-score manager (%0d errors, %0d checks)",
           errors, checks);
end

endmodule

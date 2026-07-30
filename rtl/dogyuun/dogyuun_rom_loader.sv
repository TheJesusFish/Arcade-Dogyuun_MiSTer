// Dogyuun raw parent/MRA byte stream to JTFrame SDRAM programming bridge.
module dogyuun_rom_loader #(
    parameter integer AW = 22
) (
    input                   clk,
    input                   rst,

    input                   ioctl_rom,
    input      [26:0]       ioctl_addr,
    input      [7:0]        ioctl_dout,
    input                   ioctl_wr,

    output                  dwnld_busy,
    output reg [1:0]        prog_ba,
    output reg [AW-1:0]     prog_addr,
    output reg [15:0]       prog_data,
    output reg [1:0]        prog_mask,
    output                  prog_rd,
    output reg              prog_we,
    input                   prog_rdy,
    input                   prog_ack,

    output reg              accepted,
    output reg              range_error,
    output reg              overflow_error,
    output reg [26:0]       last_addr
);

localparam [26:0] PROGRAM_END = 27'h0080000;
localparam [26:0] GP1_START   = 27'h0280000;
localparam [26:0] OKI_START   = 27'h0680000;
localparam [26:0] IMAGE_END   = 27'h06c0000;

wire in_range = ioctl_addr < IMAGE_END;
wire terminal_sentinel = ioctl_addr == IMAGE_END;
wire in_program = ioctl_addr < PROGRAM_END;
wire [1:0] target_bank = in_program ? 2'd0 :
                         (ioctl_addr < GP1_START) ? 2'd1 :
                         (ioctl_addr < OKI_START) ? 2'd2 : 2'd3;
wire [26:0] local_byte_addr = in_program ? ioctl_addr :
    (ioctl_addr < GP1_START) ? ioctl_addr - PROGRAM_END :
    (ioctl_addr < OKI_START) ? ioctl_addr - GP1_START :
                               ioctl_addr - OKI_START;
wire [21:0] local_word_addr = local_byte_addr[22:1];
wire local_lane = ~local_byte_addr[0];
wire can_accept = !prog_we || prog_ack;

assign prog_rd = 1'b0;
assign dwnld_busy = ioctl_rom || prog_we;

// prog_mask is active-low. JTFrame's byte reader maps an even ROM address to
// the SDRAM low lane, so the first byte of every source pair goes there. This
// preserves the established program/graphics transform and keeps OKI raw.
always @(posedge clk) begin
    accepted <= 1'b0;
    if (rst) begin
        prog_ba       <= 2'd0;
        prog_addr     <= {AW{1'b0}};
        prog_data     <= 16'h0000;
        prog_mask     <= 2'b11;
        prog_we       <= 1'b0;
        range_error   <= 1'b0;
        overflow_error <= 1'b0;
        last_addr     <= 27'd0;
    end else begin
        if (prog_we && prog_ack)
            prog_we <= 1'b0;

        if (ioctl_wr && ioctl_rom) begin
            last_addr <= ioctl_addr;
            if (!in_range) begin
                // JTFrame's DDR replay can emit one final strobe at the
                // reported byte length. It is an end marker, not ROM data.
                if (!terminal_sentinel)
                    range_error <= 1'b1;
            end else if (can_accept) begin
                prog_ba   <= target_bank;
                // The MRA emits GP lower/upper plane words as adjacent
                // 32-bit groups, so every SDRAM bank is programmed linearly.
                prog_addr <= local_word_addr[AW-1:0];
                prog_data <= {ioctl_dout, ioctl_dout};
                prog_mask <= local_lane ? 2'b10 : 2'b01;
                prog_we   <= 1'b1;
                accepted  <= 1'b1;
            end else begin
                overflow_error <= 1'b1;
            end
        end

        // prog_rdy is deliberately not used as an acceptance pulse. A request
        // is held stable until prog_ack; the upstream MiSTer bridge uses the
        // programming ready/write state to apply download backpressure.
    end
end

endmodule

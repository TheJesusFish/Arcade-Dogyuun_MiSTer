// Place each GP9001 lower/upper plane-word pair in one 32-bit SDRAM block.
// The logical renderer address remains identical to MAME's region layout.
module dogyuun_gfx_repack #(
    parameter integer GP_INDEX = 0
) (
    input      [21:0] logical_addr,
    output     [21:0] physical_addr
);

generate
    if (GP_INDEX == 0) begin : g_gp0
        assign physical_addr = {2'b00, logical_addr[18:0], logical_addr[19]};
    end else begin : g_gp1
        assign physical_addr = {1'b0, logical_addr[19:0], logical_addr[20]};
    end
endgenerate

endmodule

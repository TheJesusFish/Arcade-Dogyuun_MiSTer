// Exact MC68000 word-bus decode for the Dogyuun parent board map.
module dogyuun_main_decode (
    input      [23:0] addr,
    input             bus_active,
    input             rw,

    output            rom_cs,
    output            rom_read_cs,
    output            wram_cs,
    output            in1_cs,
    output            in2_cs,
    output            sys_cs,
    output            sound_ctrl_cs,
    output            shared_cs,
    output            gp0_cs,
    output            palette_cs,
    output            gp1_cs,
    output            vcount_cs,
    output            io_cs,
    output            gp_cs,
    output            mapped_cs,
    output            unmapped_cs
);

wire read_cycle = bus_active && rw;

assign rom_cs        = bus_active && (addr < 24'h080000);
assign rom_read_cs   = rom_cs && rw;
assign wram_cs       = bus_active &&
                       (addr >= 24'h100000) && (addr < 24'h104000);
assign in1_cs        = read_cycle &&
                       ((addr & 24'hfffffe) == 24'h200010);
assign in2_cs        = read_cycle &&
                       ((addr & 24'hfffffe) == 24'h200014);
assign sys_cs        = read_cycle &&
                       ((addr & 24'hfffffe) == 24'h200018);
assign sound_ctrl_cs = bus_active &&
                       ((addr & 24'hfffffe) == 24'h20001c);
assign shared_cs     = bus_active &&
                       (addr >= 24'h210000) && (addr < 24'h220000);
assign gp0_cs        = bus_active &&
                       (addr >= 24'h300000) && (addr < 24'h30000e);
assign palette_cs    = bus_active &&
                       (addr >= 24'h400000) && (addr < 24'h401000);
assign gp1_cs        = bus_active &&
                       (addr >= 24'h500000) && (addr < 24'h50000e);
assign vcount_cs     = read_cycle &&
                       ((addr & 24'hfffffe) == 24'h700000);

assign io_cs = in1_cs || in2_cs || sys_cs || sound_ctrl_cs || vcount_cs;
assign gp_cs = gp0_cs || gp1_cs;
assign mapped_cs = rom_cs || wram_cs || shared_cs || gp_cs || palette_cs ||
                   io_cs;
assign unmapped_cs = bus_active && !mapped_cs;

endmodule

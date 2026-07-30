// Dual-GP9001 line renderer. Tile and buffered-object engines run in parallel
// for each GP, then the line mixer applies internal and board-level priority.
module dogyuun_gp9001_video (
    input              clk,
    input              rst,
    input              line_start,
    input              line_commit,
    input      [8:0]   target_y,
    input              target_epoch,
    input      [8:0]   display_x,
    input      [8:0]   display_y,
    input              display_epoch,

    input      [127:0] gp0_scrolls,
    input      [127:0] gp1_scrolls,
    input      [7:0]   gp0_scroll_flip,
    input      [7:0]   gp1_scroll_flip,

    output     [12:0]  gp0_vram_addr,
    input      [15:0]  gp0_vram_data,
    output     [12:0]  gp1_vram_addr,
    input      [15:0]  gp1_vram_data,
    output     [9:0]   gp0_object_addr,
    input      [15:0]  gp0_object_data,
    output     [9:0]   gp1_object_addr,
    input      [15:0]  gp1_object_data,

    output             gp0_tile_gfx_req,
    output     [21:0]  gp0_tile_gfx_addr,
    input      [15:0]  gp0_tile_gfx_data,
    input              gp0_tile_gfx_ok,
    output             gp0_object_gfx_req,
    output     [21:0]  gp0_object_gfx_addr,
    input      [15:0]  gp0_object_gfx_data,
    input              gp0_object_gfx_ok,
    output             gp1_tile_gfx_req,
    output     [21:0]  gp1_tile_gfx_addr,
    input      [15:0]  gp1_tile_gfx_data,
    input              gp1_tile_gfx_ok,
    output             gp1_object_gfx_req,
    output     [21:0]  gp1_object_gfx_addr,
    input      [15:0]  gp1_object_gfx_data,
    input              gp1_object_gfx_ok,

    output             line_ready,
    output     [10:0]  gp0_color,
    output     [10:0]  gp1_color,
    output     [10:0]  final_color,
    output     [3:0]   engine_busy,
    output     [3:0]   deadline_miss,
    output     [15:0]  gp0_tile_cycles,
    output     [15:0]  gp0_object_cycles,
    output     [15:0]  gp1_tile_cycles,
    output     [15:0]  gp1_object_cycles,
    output     [8:0]   debug_gp0_tile_y,
    output     [8:0]   debug_gp0_object_y,
    output     [8:0]   debug_gp1_tile_y,
    output     [8:0]   debug_gp1_object_y,
    output     [3:0]   debug_line_epoch,
    output     [3:0]   debug_line_valid
);

wire [14:0] gp0_tile_pixel;
wire [14:0] gp0_object_pixel;
wire [14:0] gp1_tile_pixel;
wire [14:0] gp1_object_pixel;
wire [8:0] gp0_tile_y;
wire [8:0] gp0_object_y;
wire [8:0] gp1_tile_y;
wire [8:0] gp1_object_y;
wire gp0_tile_epoch;
wire gp0_object_epoch;
wire gp1_tile_epoch;
wire gp1_object_epoch;
wire gp0_tile_valid;
wire gp0_object_valid;
wire gp1_tile_valid;
wire gp1_object_valid;
wire [3:0] engine_done;

assign debug_gp0_tile_y = gp0_tile_y;
assign debug_gp0_object_y = gp0_object_y;
assign debug_gp1_tile_y = gp1_tile_y;
assign debug_gp1_object_y = gp1_object_y;
assign debug_line_epoch = {gp1_object_epoch, gp1_tile_epoch,
                           gp0_object_epoch, gp0_tile_epoch};
assign debug_line_valid = {gp1_object_valid, gp1_tile_valid,
                           gp0_object_valid, gp0_tile_valid};

dogyuun_gp9001_tile_line #(.GP_INDEX(0)) u_gp0_tile (
    .clk               (clk),
    .rst               (rst),
    .start             (line_start),
    .commit            (line_commit),
    .target_y          (target_y),
    .target_epoch      (target_epoch),
    .scrolls           (gp0_scrolls),
    .scroll_flip       (gp0_scroll_flip),
    .busy              (engine_busy[0]),
    .done              (engine_done[0]),
    .deadline_miss     (deadline_miss[0]),
    .last_build_cycles (gp0_tile_cycles),
    .vram_addr         (gp0_vram_addr),
    .vram_data         (gp0_vram_data),
    .gfx_req           (gp0_tile_gfx_req),
    .gfx_addr          (gp0_tile_gfx_addr),
    .gfx_data          (gp0_tile_gfx_data),
    .gfx_ok            (gp0_tile_gfx_ok),
    .scan_x            (display_x),
    .scan_pixel        (gp0_tile_pixel),
    .scan_y            (gp0_tile_y),
    .scan_epoch        (gp0_tile_epoch),
    .scan_valid        (gp0_tile_valid)
);

dogyuun_gp9001_object_line #(.GP_INDEX(0)) u_gp0_object (
    .clk               (clk),
    .rst               (rst),
    .start             (line_start),
    .commit            (line_commit),
    .target_y          (target_y),
    .target_epoch      (target_epoch),
    .scrolls           (gp0_scrolls),
    .scroll_flip       (gp0_scroll_flip),
    .busy              (engine_busy[1]),
    .done              (engine_done[1]),
    .deadline_miss     (deadline_miss[1]),
    .last_build_cycles (gp0_object_cycles),
    .object_addr       (gp0_object_addr),
    .object_data       (gp0_object_data),
    .gfx_req           (gp0_object_gfx_req),
    .gfx_addr          (gp0_object_gfx_addr),
    .gfx_data          (gp0_object_gfx_data),
    .gfx_ok            (gp0_object_gfx_ok),
    .scan_x            (display_x),
    .scan_pixel        (gp0_object_pixel),
    .scan_y            (gp0_object_y),
    .scan_epoch        (gp0_object_epoch),
    .scan_valid        (gp0_object_valid)
);

dogyuun_gp9001_tile_line #(.GP_INDEX(1)) u_gp1_tile (
    .clk               (clk),
    .rst               (rst),
    .start             (line_start),
    .commit            (line_commit),
    .target_y          (target_y),
    .target_epoch      (target_epoch),
    .scrolls           (gp1_scrolls),
    .scroll_flip       (gp1_scroll_flip),
    .busy              (engine_busy[2]),
    .done              (engine_done[2]),
    .deadline_miss     (deadline_miss[2]),
    .last_build_cycles (gp1_tile_cycles),
    .vram_addr         (gp1_vram_addr),
    .vram_data         (gp1_vram_data),
    .gfx_req           (gp1_tile_gfx_req),
    .gfx_addr          (gp1_tile_gfx_addr),
    .gfx_data          (gp1_tile_gfx_data),
    .gfx_ok            (gp1_tile_gfx_ok),
    .scan_x            (display_x),
    .scan_pixel        (gp1_tile_pixel),
    .scan_y            (gp1_tile_y),
    .scan_epoch        (gp1_tile_epoch),
    .scan_valid        (gp1_tile_valid)
);

dogyuun_gp9001_object_line #(.GP_INDEX(1)) u_gp1_object (
    .clk               (clk),
    .rst               (rst),
    .start             (line_start),
    .commit            (line_commit),
    .target_y          (target_y),
    .target_epoch      (target_epoch),
    .scrolls           (gp1_scrolls),
    .scroll_flip       (gp1_scroll_flip),
    .busy              (engine_busy[3]),
    .done              (engine_done[3]),
    .deadline_miss     (deadline_miss[3]),
    .last_build_cycles (gp1_object_cycles),
    .object_addr       (gp1_object_addr),
    .object_data       (gp1_object_data),
    .gfx_req           (gp1_object_gfx_req),
    .gfx_addr          (gp1_object_gfx_addr),
    .gfx_data          (gp1_object_gfx_data),
    .gfx_ok            (gp1_object_gfx_ok),
    .scan_x            (display_x),
    .scan_pixel        (gp1_object_pixel),
    .scan_y            (gp1_object_y),
    .scan_epoch        (gp1_object_epoch),
    .scan_valid        (gp1_object_valid)
);

dogyuun_gp9001_line_mixer u_mixer (
    .display_y        (display_y),
    .display_epoch    (display_epoch),
    .gp0_tile_pixel   (gp0_tile_pixel),
    .gp0_tile_y       (gp0_tile_y),
    .gp0_tile_epoch   (gp0_tile_epoch),
    .gp0_tile_valid   (gp0_tile_valid),
    .gp0_object_pixel (gp0_object_pixel),
    .gp0_object_y     (gp0_object_y),
    .gp0_object_epoch (gp0_object_epoch),
    .gp0_object_valid (gp0_object_valid),
    .gp1_tile_pixel   (gp1_tile_pixel),
    .gp1_tile_y       (gp1_tile_y),
    .gp1_tile_epoch   (gp1_tile_epoch),
    .gp1_tile_valid   (gp1_tile_valid),
    .gp1_object_pixel (gp1_object_pixel),
    .gp1_object_y     (gp1_object_y),
    .gp1_object_epoch (gp1_object_epoch),
    .gp1_object_valid (gp1_object_valid),
    .line_ready       (line_ready),
    .gp0_color        (gp0_color),
    .gp1_color        (gp1_color),
    .final_color      (final_color)
);

endmodule

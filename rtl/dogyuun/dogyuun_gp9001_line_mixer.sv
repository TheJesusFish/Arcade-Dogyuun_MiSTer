// Per-GP tile/object priority followed by Dogyuun's board-level GP order.
// MAME clears, renders GP1, clears priority, then renders opaque GP0 pixels.
module dogyuun_gp9001_line_mixer (
    input      [8:0]  display_y,
    input             display_epoch,

    input      [14:0] gp0_tile_pixel,
    input      [8:0]  gp0_tile_y,
    input             gp0_tile_epoch,
    input             gp0_tile_valid,
    input      [14:0] gp0_object_pixel,
    input      [8:0]  gp0_object_y,
    input             gp0_object_epoch,
    input             gp0_object_valid,

    input      [14:0] gp1_tile_pixel,
    input      [8:0]  gp1_tile_y,
    input             gp1_tile_epoch,
    input             gp1_tile_valid,
    input      [14:0] gp1_object_pixel,
    input      [8:0]  gp1_object_y,
    input             gp1_object_epoch,
    input             gp1_object_valid,

    output            line_ready,
    output     [10:0] gp0_color,
    output     [10:0] gp1_color,
    output     [10:0] final_color
);

function automatic [14:0] mix_gp;
    input [14:0] tile_pixel;
    input [14:0] object_pixel;
    begin
        if ((object_pixel[3:0] != 4'h0) &&
            (object_pixel[14:11] >= tile_pixel[14:11]))
            mix_gp = object_pixel;
        else
            mix_gp = tile_pixel;
    end
endfunction

wire gp0_ready = gp0_tile_valid && gp0_object_valid &&
                 (gp0_tile_y == display_y) &&
                 (gp0_object_y == display_y) &&
                 (gp0_tile_epoch == display_epoch) &&
                 (gp0_object_epoch == display_epoch);
wire gp1_ready = gp1_tile_valid && gp1_object_valid &&
                 (gp1_tile_y == display_y) &&
                 (gp1_object_y == display_y) &&
                 (gp1_tile_epoch == display_epoch) &&
                 (gp1_object_epoch == display_epoch);

wire [14:0] gp0_mixed = mix_gp(gp0_tile_pixel, gp0_object_pixel);
wire [14:0] gp1_mixed = mix_gp(gp1_tile_pixel, gp1_object_pixel);

assign line_ready = gp0_ready && gp1_ready;
assign gp0_color = gp0_ready ? gp0_mixed[10:0] : 11'd0;
assign gp1_color = gp1_ready ? gp1_mixed[10:0] : 11'd0;
assign final_color = line_ready ?
    ((gp0_mixed[3:0] != 4'h0) ? gp0_mixed[10:0] : gp1_mixed[10:0]) :
    11'd0;

endmodule

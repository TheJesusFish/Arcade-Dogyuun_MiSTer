// Convert JTFrame's active-low controls to the active-high TP-030 input words.
module dogyuun_inputs (
    input      [6:0]  joy1_n,
    input      [6:0]  joy2_n,
    input      [3:0]  start_n,
    input      [3:0]  coin_n,
    input             service_n,
    input             tilt_n,
    input             test_n,
    output     [15:0] in1,
    output     [15:0] in2,
    output     [15:0] sys
);

function automatic [7:0] player_port;
    input [6:0] joy_n;
    begin
        // MAME/Toaplan: U,D,L,R,B1,B2,B3,unknown.
        player_port = {1'b0,
                       ~joy_n[6], ~joy_n[5], ~joy_n[4],
                       ~joy_n[0], ~joy_n[1], ~joy_n[2], ~joy_n[3]};
    end
endfunction

assign in1 = {8'h00, player_port(joy1_n)};
assign in2 = {8'h00, player_port(joy2_n)};
assign sys = {8'h00,
              1'b0,
              ~start_n[1], ~start_n[0],
              ~coin_n[1], ~coin_n[0],
              ~test_n, ~tilt_n, ~service_n};

endmodule

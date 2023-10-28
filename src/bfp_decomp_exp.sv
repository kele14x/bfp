`timescale 1 ns / 1 ps
//
`default_nettype none

module bfp_decomp_exp (
    input var         clk,
    input var         rst,
    //
    input var  [ 3:0] din_width,
    input var  [63:0] din_data,
    input var         din_valid,
    input var         din_last,
    input var  [31:0] din_user,
    //
    output var [63:0] m_axis_tdata,
    output var [ 7:0] m_axis_tkeep,
    output var        m_axis_tvalid,
    output var        m_axis_tlast,
    output var [31:0] m_axis_tuser,
    //
    input var  [ 3:0] ctrl_extra_shift
);

  logic [ 3:0] exp;

  logic [15:0] data0      [4];
  logic [ 3:0] width0;
  logic [ 3:0] shift0;

  logic [30:0] data1      [4];
  logic [15:0] data2      [4];

  logic [ 3:0] state;

  logic        din_valid_d[3];
  logic        din_last_d [3];
  logic [31:0] din_user_d [3];

  //
  // This function saturate signed 31-bit to 16-bit
  //
  function static logic [15:0] saturate(input logic [30:0] din);
    if (din[30:15] == '0 || din[30:15] == '1) begin
      saturate = din[15:0];
    end else if (din[30] == 1'b0) begin
      saturate = 16'h7FFF;
    end else begin
      saturate = 16'h8000;
    end
  endfunction

  //
  // This function get bit_mask by bit width
  //
  function static logic [15:0] bit_mask(input logic [3:0] width);
    case (width)
      4'd1:    bit_mask = 16'h8000;
      4'd2:    bit_mask = 16'hC000;
      4'd3:    bit_mask = 16'hE000;
      4'd4:    bit_mask = 16'hF000;
      4'd5:    bit_mask = 16'hF800;
      4'd6:    bit_mask = 16'hFC00;
      4'd7:    bit_mask = 16'hFE00;
      4'd8:    bit_mask = 16'hFF00;
      4'd9:    bit_mask = 16'hFF80;
      4'd10:   bit_mask = 16'hFFC0;
      4'd11:   bit_mask = 16'hFFE0;
      4'd12:   bit_mask = 16'hFFF0;
      4'd13:   bit_mask = 16'hFFF8;
      4'd14:   bit_mask = 16'hFFFC;
      4'd15:   bit_mask = 16'hFFFE;
      default: bit_mask = 16'hFFFF;
    endcase
  endfunction

  //
  // Bit extract by shifting and masking
  //
  function static logic [15:0] bit_extract(input int i, input logic [3:0] width,
                                           input logic [63:0] din);
    logic [63:0] temp;
    if (width == 0) begin
      temp = (din << (64 - 16 * (4 - i)));
    end else begin
      temp = (din << (64 - width * (4 - i)));
    end
    bit_extract = temp[63:48] & bit_mask(width);
  endfunction

  // We need to count how may REs are received
  // 2 REs / tick and 6 tick / 1 RB
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= '0;
    end else if (din_valid && din_last) begin
      state <= '0;
    end else if (din_valid) begin
      state <= (state == 5 ? 0 : state + 1);
    end
  end

  always_comb begin
    if (din_width == 0) begin
      exp = 0;
    end else begin
      exp = din_data >> (din_width * 4);
    end
  end

  generate
    for (genvar i = 0; i < 4; i++) begin : g_bit_extract
      always_ff @(posedge clk) begin
        data0[i] <= bit_extract(i, din_width, din_data);
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    width0 <= din_width;
  end

  always_ff @(posedge clk) begin
    if (state == 0) begin
      shift0 <= (31 - exp - din_width - ctrl_extra_shift);
    end
  end

  generate
    for (genvar i = 0; i < 4; i++) begin : g_shift
      // Shift right with sign extend
      always_ff @(posedge clk) begin
        data1[i] <= $signed({data0[i], 15'b0}) >>> shift0;
      end
    end
  endgenerate

  generate
    for (genvar i = 0; i < 4; i++) begin : g_saturate
      // Saturate
      always_ff @(posedge clk) begin
        data2[i] <= saturate(data1[i]);
      end
    end
  endgenerate


  // Output
  //-------

  // TDATA

  assign m_axis_tdata = {
    data2[3][7:0],
    data2[3][15:8],  // Q1
    data2[2][7:0],
    data2[2][15:8],  // I1
    data2[1][7:0],
    data2[1][15:8],  // Q0
    data2[0][7:0],
    data2[0][15:8]  // I0
  };

  // TKEEP

  assign m_axis_tkeep = '1;

  // TVALID

  always_ff @(posedge clk) begin
    din_valid_d <= {din_valid, din_valid_d[0:1]};
  end

  assign m_axis_tvalid = din_valid_d[2];

  // TLAST

  always_ff @(posedge clk) begin
    din_last_d <= {din_last, din_last_d[0:1]};
  end

  assign m_axis_tlast = din_last_d[2];

  // TUSER

  always_ff @(posedge clk) begin
    din_user_d <= {din_user, din_user_d[0:1]};
  end

  assign m_axis_tuser = din_user_d[2];

endmodule

`default_nettype wire

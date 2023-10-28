`timescale 1 ns / 1 ps
//
`default_nettype none

module bfp_comp (
    input var         clk,
    input var         rst,
    //
    input var  [63:0] s_axis_tdata,
    input var  [ 7:0] s_axis_tkeep,
    input var         s_axis_tvalid,
    input var         s_axis_tlast,
    input var  [31:0] s_axis_tuser,
    //
    output var [63:0] m_axis_tdata,
    output var [ 7:0] m_axis_tkeep,
    output var        m_axis_tvalid,
    output var        m_axis_tlast,
    output var [31:0] m_axis_tuser,
    // Control
    //--------
    input var  [ 3:0] ctrl_ud_comp_meth,
    input var  [ 3:0] ctrl_ud_iq_width
);

  //
  // This function does byte reverse for AXI-Stream TDATA signal
  //
  function static logic [63:0] byte_reverse(input logic [63:0] din);
    for (int i = 0; i < 8; i++) begin
      byte_reverse[63-8*i-:8] = din[8*i+7-:8];
    end
  endfunction

  //
  // This function get the max value out of 2
  //
  function static logic [15:0] get_max2(input logic [15:0] din[2]);
    logic [15:0] d0;
    logic [15:0] d1;
    d0 = din[0][15] ? ~din[0] : din[0];
    d1 = din[1][15] ? ~din[1] : din[1];
    return d0 > d1 ? d0 : d1;
  endfunction

  //
  // This function get the max value out of 4
  //
  function static logic [15:0] get_max4(input logic [15:0] din[4]);
    logic [15:0] d0;
    logic [15:0] d1;
    d0 = get_max2(din[0:1]);
    d1 = get_max2(din[2:3]);
    return d0 > d1 ? d0 : d1;
  endfunction

  //
  // This function get MSB position of input data
  //
  function static logic [3:0] get_msb(input logic [15:0] din);
    for (int i = 15; i > 0; i--) begin
      if (din[i] ^ din[i-1]) return i;
    end
    return 0;
  endfunction

  //
  // This function get shift value
  //
  function static logic [3:0] get_shift(input logic [3:0] msb, input logic [3:0] width);
    get_shift = width == 0 ? 0 : 15 - msb;
    get_shift = get_shift < 16 - width ? get_shift : 16 - width;
  endfunction

  //
  // This function get the exp value of input data
  //
  function static logic [3:0] get_exp(input logic [3:0] msb, input logic [3:0] width);
    logic [4:0] temp;
    if (width == '0) begin
      temp = '0;
    end else begin
      temp = {1'b0, msb} - width + 1;
    end
    return temp[4] ? 0 : temp[3:0];
  endfunction

  //
  // This function caclulates the rounding mask
  //
  function static logic [15:0] get_mask(input logic [3:0] w);
    logic [15:0] mask;
    case (w)
      0: mask = 16'h0000;
      1: mask = 16'h7FFF;
      2: mask = 16'h3FFF;
      3: mask = 16'h1FFF;
      4: mask = 16'h0FFF;
      5: mask = 16'h07FF;
      6: mask = 16'h03FF;
      7: mask = 16'h01FF;
      8: mask = 16'h00FF;
      9: mask = 16'h007F;
      10: mask = 16'h003F;
      11: mask = 16'h001F;
      12: mask = 16'h000F;
      13: mask = 16'h0007;
      14: mask = 16'h0003;
      default: mask = 16'h0001;
    endcase
    return mask;
  endfunction


  // Control CDC
  //------------

  logic [3:0] ud_iq_width;

  always_ff @(posedge clk) begin
    if (ctrl_ud_comp_meth == 1) begin
      // BFPx
      ud_iq_width = ctrl_ud_iq_width;
    end else begin
      // Uncompressed, or not supported compression method
      ud_iq_width = '0;
    end
  end


  // Main
  //-----

  // r0: state

  logic [63:0] s_axis_tdata_reversed;

  logic        sync0;
  logic [ 2:0] state0;
  logic [15:0] data0                 [4];

  assign s_axis_tdata_reversed = byte_reverse(s_axis_tdata);

  always_ff @(posedge clk) begin
    if (rst || (s_axis_tvalid && s_axis_tlast)) begin
      sync0 <= 1'b0;
    end else if (s_axis_tvalid) begin
      sync0 <= 1'b0;
    end
  end

  // This is state0 has 0/1/2/3/4/5 and sync with input
  always_ff @(posedge clk) begin
    if (rst || (s_axis_tvalid && s_axis_tlast)) begin
      state0 <= '0;
    end else if (s_axis_tvalid) begin
      state0 <= state0 == 5 ? 0 : state0 + 1;
    end
  end

  generate
    for (genvar i = 0; i < 4; i++) begin : g_data0
      assign data0[i] = s_axis_tdata_reversed[63-i*16-:16];
    end
  endgenerate

  // r1: get max of 4

  logic [15:0] max1;
  logic [ 2:0] state1;
  logic        valid1;

  always_ff @(posedge clk) begin
    max1 <= get_max4(data0);
  end

  always_ff @(posedge clk) begin
    state1 <= state0;
  end

  always_ff @(posedge clk) begin
    valid1 <= s_axis_tvalid;
  end

  // r2: max of 6 state (1 RB)

  logic [15:0] max2;
  logic [ 2:0] state2;
  logic        valid2;

  always_ff @(posedge clk) begin
    if (valid1) begin
      if (state1 == 0) begin
        max2 <= max1;
      end else begin
        max2 <= get_max2('{max1, max2});
      end
    end
  end

  always_ff @(posedge clk) begin
    state2 <= state1;
  end

  always_ff @(posedge clk) begin
    valid2 <= valid1;
  end

  // r3: get shift value

  logic [64:0] fifo3;
  logic [15:0] mask3;
  logic [15:0] data3  [4];
  logic [ 3:0] shift3;
  logic [ 3:0] exp3;
  logic [ 2:0] state3;
  logic        valid3;
  logic        sync3;
  logic        last3;

  always_ff @(posedge clk) begin
    mask3 <= get_mask(ud_iq_width) >> 1;
  end

  generate
    for (genvar i = 0; i < 4; i++) begin : g_data3
      assign data3[i] = fifo3[63-i*16-:16];
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (valid2 && state2 == 5) begin
      shift3 <= get_shift(get_msb(max2), ud_iq_width);
      exp3   <= get_exp(get_msb(max2), ud_iq_width);
    end
  end

  always_ff @(posedge clk) begin
    if (valid2 && state2 == 5) begin
      state3 <= 'd0;
    end else if (valid3) begin
      state3 <= state3 + 1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      valid3 <= 1'b0;
    end else if (valid2 && state2 == 5) begin
      valid3 <= 1'b1;
    end else if (state3 == 5) begin
      valid3 <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      sync3 <= 1'b0;
    end else if (valid3 && last3) begin
      sync3 <= 1'b0;
    end else if (valid3) begin
      sync3 <= 1'b1;
    end
  end

  assign last3 = fifo3[64];

  // r4: shifting to remove msb, get shift4 value

  logic [15:0] mask4;
  logic [15:0] data4  [4];
  logic [ 3:0] exp4;
  logic [ 2:0] state4;
  logic        valid4;
  logic        sync4;
  logic        last4;

  always_ff @(posedge clk) begin
    mask4 <= ~get_mask(ud_iq_width);
  end

  generate
    for (genvar i = 0; i < 4; i++) begin : g_data4
      always_ff @(posedge clk) begin
        data4[i] <= (data3[i] << shift3) | mask3;
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    exp4 <= exp3;
  end

  always_ff @(posedge clk) begin
    state4 <= state3;
  end

  always_ff @(posedge clk) begin
    valid4 <= valid3;
  end

  always_ff @(posedge clk) begin
    sync4 <= sync3;
  end

  always_ff @(posedge clk) begin
    last4 <= last3;
  end

  // r5: rounding, and calculate shift5 value

  logic [63:0] data5_or;
  logic [63:0] data5_shift[4];
  logic [15:0] data5      [4];
  logic [ 6:0] shift5     [4];
  logic [ 3:0] exp5;
  logic [ 2:0] state5;
  logic        valid5;
  logic        sync5;
  logic        last5;

  generate
    for (genvar i = 0; i < 4; i++) begin : g_data5

      always_ff @(posedge clk) begin
        if (data4[i] == 16'h7FFF) begin
          data5[i] <= data4[i] & mask4;
        end else begin
          // TODO: test
          // data5[i] <= (data4[i] + 1) & mask4 | mask4;
          data5[i] <= (data4[i] + 1) & mask4;
        end
      end

      always_comb begin
        data5_shift[i] = {data5[i], 48'b0} >> shift5[i];
      end

    end
  endgenerate

  always_comb begin
    if (state5 == 0) begin
      data5_or = {4'b0, exp5, 56'b0};
    end else begin
      data5_or = 64'b0;
    end
    //
    for (int i = 0; i < 4; i++) begin
      data5_or = data5_or | data5_shift[i];
    end
  end

  generate
    for (genvar i = 0; i < 4; i++) begin : g_shift5
      always_ff @(posedge clk) begin
        if (state4 == 0) begin
          shift5[i] <= i * ud_iq_width + 8;
        end else begin
          shift5[i] <= i * ud_iq_width;
        end
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    exp5 <= exp4;
  end

  always_ff @(posedge clk) begin
    state5 <= state4;
  end

  always_ff @(posedge clk) begin
    valid5 <= valid4;
  end

  always_ff @(posedge clk) begin
    sync5 <= sync4;
  end

  always_ff @(posedge clk) begin
    last5 <= last4;
  end

  // r6: shifting to remap bits

  logic [31:0] fifo6;
  logic [63:0] data6;
  logic [63:0] data6_shift;
  logic [63:0] data6_shift_f;
  logic [ 6:0] cnt6;
  logic [ 6:0] cnt6_next;
  logic [ 5:0] shift6;
  logic [ 2:0] state6;
  logic        valid6;
  logic        sync6;
  logic        last6;
  logic        last6_extra;

  always_ff @(posedge clk) begin
    data6 <= data5_or;
  end

  assign {data6_shift, data6_shift_f} = {data6, 64'b0} >> shift6;

  always_ff @(posedge clk) begin
    if (rst) begin
      cnt6 <= '0;
    end else if (valid6 && last6 && cnt6_next > 64) begin
      cnt6 <= cnt6_next;
    end else if (valid6 && last6) begin
      cnt6 <= '0;
    end else if (valid6) begin
      cnt6 <= cnt6_next;
    end else if (last6_extra) begin
      cnt6 <= '0;
    end
  end

  always_comb begin
    if (state6 == 0) begin
      cnt6_next = cnt6[5:0] + 8 + 4 * ud_iq_width;
    end else begin
      cnt6_next = cnt6[5:0] + 4 * ud_iq_width;
    end
  end

  assign shift6 = cnt6[5:0];

  always_ff @(posedge clk) begin
    state6 <= state5;
  end

  always_ff @(posedge clk) begin
    valid6 <= valid5;
  end

  always_ff @(posedge clk) begin
    sync6 <= sync5;
  end

  always_ff @(posedge clk) begin
    last6 <= last5;
  end

  always_ff @(posedge clk) begin
    last6_extra <= valid6 && last6 && (cnt6_next > 64);
  end

  // r7: final data

  logic [63:0] data7;
  logic [63:0] data7_f;
  logic        valid7;
  logic        last7;

  always_ff @(posedge clk) begin
    if (valid6 || last6_extra) begin
      if (last6_extra) begin
        data7 <= data7_f | data6_shift;
      end else if (~sync6) begin
        data7 <= data6_shift;
      end else if (cnt6[6]) begin
        data7 <= data7_f | data6_shift;
      end else begin
        data7 <= data7 | data6_shift;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (valid6) begin
      if (~sync6) begin
        data7_f <= '0;
      end else begin
        data7_f <= data6_shift_f;
      end
    end
  end

  always_ff @(posedge clk) begin
    valid7 <= (cnt6_next[6] && valid6) || last6_extra;
  end

  always_ff @(posedge clk) begin
    if (valid6 && last6 && cnt6_next <= 64) begin
      last7 <= 1'b1;
    end else if (last6_extra) begin
      last7 <= 1'b1;
    end else if (valid6) begin
      last7 <= 1'b0;
    end
  end

  // output

  assign m_axis_tdata  = byte_reverse(data7);
  assign m_axis_tlast  = last7;
  assign m_axis_tvalid = valid7;

  // TODO: tkeep?

  always_ff @(posedge clk) begin
    if (valid6 && ~sync6) begin
      m_axis_tuser <= fifo6;
    end
  end

  // Store data in SRL FIFO
  //-----------------------

  // The full/empty state is not check as we know the FIFO will never full
  // and we will be read at right time

  fifo_srl #(
      .DATA_WIDTH(65)
  ) i_data_fifo (
      .clk  (clk),
      .rst  (rst),
      //
      .din  ({s_axis_tlast, s_axis_tdata_reversed}),
      .wr_en(s_axis_tvalid),
      .full (  /* not used */),
      //
      .dout (fifo3),
      .empty(  /* not used */),
      .rd_en(valid3)
  );

  fifo_srl #(
      .DATA_WIDTH(32)
  ) i_user_fifo (
      .clk  (clk),
      .rst  (rst),
      //
      .din  (s_axis_tuser),
      .wr_en(s_axis_tvalid && ~sync0),
      .full (  /* not used */),
      //
      .dout (fifo6),
      .empty(  /* not used */),
      .rd_en(valid6 && ~sync6)
  );

endmodule

`default_nettype wire

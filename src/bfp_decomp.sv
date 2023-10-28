`timescale 1 ns / 1 ps
//
`default_nettype none

module bfp_decomp (
    input var         clk,
    input var         rst,
    //
    input var  [63:0] s_axis_tdata,
    input var  [ 7:0] s_axis_tkeep,
    input var         s_axis_tvalid,
    input var         s_axis_tlast,
    output var        s_axis_tready,
    input var  [39:0] s_axis_tuser,         // {udCompHdr, sectionHdr}
    //
    output var [63:0] m_axis_tdata,
    output var [ 7:0] m_axis_tkeep,
    output var        m_axis_tvalid,
    output var        m_axis_tlast,
    output var [31:0] m_axis_tuser,         // {sectionHdr}
    //
    input var  [ 3:0] ctrl_extra_shift,
    //
    output var        err_unexpected_tlast
);

  logic [ 3:0] d0_width;
  logic [63:0] d0_data;
  logic        d0_valid;
  logic        d0_last;
  logic [31:0] d0_user;

  oran_deframer_dl_ss_decomp_gearbox i_gearbox (
      .clk                 (clk),
      .rst                 (rst),
      //
      .s_axis_tdata        (s_axis_tdata),
      .s_axis_tkeep        (s_axis_tkeep),
      .s_axis_tvalid       (s_axis_tvalid),
      .s_axis_tlast        (s_axis_tlast),
      .s_axis_tready       (s_axis_tready),
      .s_axis_tuser        (s_axis_tuser),
      //
      .dout_width          (d0_width),
      .dout_data           (d0_data),
      .dout_valid          (d0_valid),
      .dout_last           (d0_last),
      .dout_user           (d0_user),
      //
      .err_unexpected_tlast()
  );

  oran_deframer_dl_ss_decomp_exp i_exp (
      .clk             (clk),
      .rst             (rst),
      //
      .din_width       (d0_width),
      .din_data        (d0_data),
      .din_valid       (d0_valid),
      .din_last        (d0_last),
      .din_user        (d0_user),
      //
      .m_axis_tdata    (m_axis_tdata),
      .m_axis_tkeep    (m_axis_tkeep),
      .m_axis_tvalid   (m_axis_tvalid),
      .m_axis_tlast    (m_axis_tlast),
      .m_axis_tuser    (m_axis_tuser),
      //
      .ctrl_extra_shift(ctrl_extra_shift)
  );

endmodule

`default_nettype wire

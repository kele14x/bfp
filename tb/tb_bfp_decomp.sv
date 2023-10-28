`timescale 1 ns / 1 ps
//
`default_nettype none

module tb_bfp_decomp;

  logic        clk;
  logic        rst;

  logic [63:0] s_axis_tdata;
  logic [ 7:0] s_axis_tkeep;
  logic        s_axis_tvalid;
  logic        s_axis_tlast;
  logic        s_axis_tready;
  logic [31:0] s_axis_tuser;

  logic [63:0] m_axis_tdata;
  logic [ 7:0] m_axis_tkeep;
  logic        m_axis_tvalid;
  logic        m_axis_tlast;
  logic [31:0] m_axis_tuser;

  logic [ 3:0] ctrl_ud_comp_meth = 1;
  logic [ 3:0] ctrl_ud_iq_width = 9;
  logic [ 3:0] ctrl_fs_offset = 0;


  logic [63:0] test_in               [1024];
  logic [63:0] test_ref_out          [1024];


  //
  // Reset the AXIS Master interface
  //
  task static reset();
    s_axis_tdata  <= 0;
    s_axis_tkeep  <= 0;
    s_axis_tvalid <= 0;
    s_axis_tlast  <= 0;
    s_axis_tuser  <= 0;
  endtask

  //
  // Send a packet
  //
  task static send_packet(input int nPRBu);
    int b = nPRBu * (1 + ctrl_ud_iq_width * 3); // number of bytes
    int w = (b + 7) / 8;  // number of words
    int r = b % 8; // number of bytes in last word

    for (int i = 0; i < w; i++) begin
      s_axis_tdata  <= test_in[i];
      for (int j = 0; j < 8; j++) begin
        s_axis_tkeep[j] <= j < r | i < w - 1;
      end
      s_axis_tvalid <= 1'b1;
      s_axis_tlast  <= i == w - 1;
      s_axis_tuser  <= '0;
      forever begin
        @(posedge clk);
        if (s_axis_tready) begin
          break;
        end
      end
    end
    // Reset interface
    reset();
  endtask

  initial begin
    $readmemh("test_bfp_comp_out.txt", test_in, 0, 179);
    $readmemh("test_bfp_comp_in.txt", test_ref_out, 0, 306);
  end


  // Main
  //-----

  initial begin
    clk = 0;
    forever begin
      #5 clk = ~clk;
    end
  end

  initial begin
    rst = 1;
    #100;
    rst = 0;
  end

  initial begin
    reset();
    wait (rst == 0);
    #100;

    @(posedge clk);
    send_packet(1);
    #1000;
    $finish();
  end

  initial begin
    wait (rst == 0);
    forever begin
      @(posedge clk);
      if (m_axis_tvalid) begin
        $display("TDATA, TKEEP = %x, %x", m_axis_tdata, m_axis_tkeep);
        if (m_axis_tlast) $display("**EOP\n");
      end
    end
  end

  bfp_decomp DUT (.*);

endmodule

`default_nettype wire

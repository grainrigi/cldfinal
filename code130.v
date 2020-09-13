/**************************************************************************/
/* code130.v                          For CSC.T341 CLD Archlab TOKYO TECH */
/**************************************************************************/
`timescale 1ns/100ps
`default_nettype none

`define BEQ 6'h4
`define BNE 6'h5
`define NOP 32'h20

`ifdef IVERILOG
/***** top module for simulation *****/
module m_top (); 
   reg r_clk=0; initial forever #50 r_clk = ~r_clk;
   wire [31:0] w_led;

   initial $dumpfile("main.vcd");
   initial $dumpvars(0, m_top);

   m_proc11 p (r_clk, w_led);
   /*
   initial $write("time: s r_pc     w_ir     w_rrs    w_rrt2   r_rslt2  r_led\n");
   always@(posedge r_clk) $write("%4d: %d %x %x %x %x %x %x\n", $time,
                         p.r_state, p.r_pc, p.w_ir, p.w_rrs, p.w_rrt2, p.w_rslt2, w_led);
                      */
   initial #10000 $finish;
endmodule

`else
/***** main module for FPGA implementation *****/
module m_main (w_clk, w_led);
   input  wire w_clk;
   output wire [3:0] w_led;
 
   wire w_clk2, w_locked;
   clk_wiz_0 clk_w0 (w_clk2, 0, w_locked, w_clk);
   
   wire [31:0] w_dout;
   m_proc11 p (w_clk2, w_dout);

   vio_0 vio_00(w_clk2, w_dout);
 
   reg [3:0] r_led = 0;
   always @(posedge w_clk2) 
     r_led <= {^w_dout[31:24], ^w_dout[23:16], ^w_dout[15:8], ^w_dout[7:0]};
   assign w_led = r_led;
endmodule
`endif

module m_memory (w_clk, w_addr, w_we, w_din, r_dout);
   input  wire w_clk, w_we;
   input  wire [10:0] w_addr;
   input  wire [31:0] w_din;
   output reg [31:0] r_dout = 0;
   reg [31:0] 	      cm_ram [0:2047]; // 4K word (2048 x 32bit) memory
   always @(posedge w_clk) if (w_we) cm_ram[w_addr] <= w_din;
   always @(posedge w_clk) r_dout <= cm_ram[w_addr];
`include "program.txt"
endmodule

module m_regfile (w_clk, w_rr1, w_rr2, w_wr, w_we, w_wdata, w_rdata1, w_rdata2);
   input  wire        w_clk;
   input  wire [4:0]  w_rr1, w_rr2, w_wr;
   input  wire [31:0] w_wdata;
   input  wire        w_we;
   output wire [31:0] w_rdata1, w_rdata2;
    
   reg [31:0] r[0:31];
   assign w_rdata1 = (w_rr1==0) ? 0 : r[w_rr1];
   assign w_rdata2 = (w_rr2==0) ? 0 : r[w_rr2];
   always @(posedge w_clk) if(w_we) r[w_wr] <= w_wdata;
   
   initial r[0] = 0;
endmodule

module m_predictor (w_clk, w_baddr, w_br, w_be, w_paddr, w_pr, w_pre);
  input  wire        w_clk;
  input  wire [10:0] w_baddr, w_br;
  input  wire        w_be;
  input  wire [10:0] w_paddr;
  output wire [10:0] w_pr;
  output wire        w_pre;

  reg [10:0] r_addr[0:1];
  reg        r_priority[0:1];
  reg [10:0] r_predict[0:1];
  generate genvar g;
    for (g = 0; g < 2; g = g + 1) begin : Gen
      initial r_addr[g] = 11'b11111111111;
      initial r_priority[g] = g;
      initial r_predict[g] = 0;
    end
  endgenerate

  // internal
  wire [1:0] w_bselect = (r_addr[0] == w_baddr) ? 0
                       : (r_addr[1] == w_baddr) ? 1
                       : 2;
  wire w_bpriority = r_priority[w_bselect[0]];
  wire [1:0] w_pselect = (r_addr[0] == w_paddr) ? 0
                       : (r_addr[1] == w_paddr) ? 1
                       : 2;
  
  // update table
  always @(posedge w_clk) if (w_be == 1) begin
    if (w_bselect != 2) begin
      r_predict[w_bselect] <= #3 w_br;
      // update priority
      r_priority[0] <= #3 (w_bselect == 0) ? 0 : 1;
      r_priority[1] <= #3 (w_bselect == 1) ? 0 : 1;
    end
    else begin
      if (r_priority[0] == 1) begin
        r_addr[0] <= #3 w_baddr;
        r_predict[0] <= #3 w_br;
      end
      if (r_priority[1] == 1) begin
        r_addr[1] <= #3 w_baddr;
        r_predict[1] <= #3 w_br;
      end
      // update priority
      r_priority[0] <= #3 (r_priority[0] == 1) ? 0 : 1;
      r_priority[1] <= #3 (r_priority[1] == 1) ? 0 : 1;
    end
  end

  // fetch prediction
  assign w_pr = r_predict[w_pselect[0]];
  assign w_pre = w_pselect != 2;
endmodule

module m_proc11 (w_clk, r_rout);
  input wire w_clk;
  output reg [31:0] r_rout;

  reg r_halt = 0, r_stall = 0;
  wire w_be;
  wire w_rst = 0;
  reg [31:0] IfId_pc4=0; // pipe regs
  reg [31:0] IdEx_rrs=0, IdEx_rrt=0, IdEx_rrt2=0; //
  reg [31:0] ExMe_rslt=0, ExMe_rrt=0; //
  reg [31:0] MeWb_rslt=0; //
  reg [5:0] IdEx_op=0, ExMe_op=0, MeWb_op=0; //
  reg [31:0] IfId_pc=0, IdEx_pc=0, ExMe_pc=0, MeWb_pc=0; //
  reg [4:0] IdEx_rs=0;
  reg [4:0] IdEx_rt=0, ExMe_rt=0;
  reg [4:0] IfId_rd2=0, IdEx_rd2=0, ExMe_rd2=0, MeWb_rd2=0;//
  reg IfId_w=0, IdEx_w=0, ExMe_w=0, MeWb_w=0; //
  reg IfId_we=0, IdEx_we=0, ExMe_we=0; //
  reg IfId_pre=0;
  wire [31:0] IfId_ir, MeWb_ldd; // note
  /**************************** IF stage **********************************/
  wire [10:0] w_pr;
  wire w_taken, w_pre;
  wire [31:0] w_tpc, w_npc, w_ir;
  reg [31:0] r_pc = 0, r_id_interlock_ir = 0;
  wire [31:0] w_pc4 = r_pc + 4;
  reg r_id_interlock = 0;
  m_memory m_imem (w_clk, r_pc[12:2], 1'd0, 32'd0, w_ir);
  assign w_npc = (w_rst | r_halt) ? 0 :
                 (w_id_interlock) ? r_pc :
                 (w_pre) ? {19'h0, w_pr, 2'h0} :
                 ((!IfId_pre || w_pr_fail) && w_taken) ? w_tpc : w_pc4;
  assign IfId_ir = (r_id_interlock) ? r_id_interlock_ir : (r_stall) ? `NOP : w_ir;
  always @(posedge w_clk) begin
    r_pc <= #3 w_npc;
    r_id_interlock <= w_id_interlock;
    r_id_interlock_ir <= w_ir; 
    if (!w_id_interlock) begin
      IfId_pc <= #3 r_pc;
      IfId_pc4 <= #3 w_pc4;
    end
    IfId_pre <= #3 w_pre;
  end
  /**************************** ID stage ***********************************/
  wire [31:0] w_rrs, w_rrt, w_rslt2;
  wire [5:0] w_op = IfId_ir[31:26];
  wire [4:0] w_rs = IfId_ir[25:21];
  wire [4:0] w_rt = IfId_ir[20:16];
  wire [4:0] w_rd = IfId_ir[15:11];
  wire [4:0] w_rd2 = (w_op!=0) ? w_rt : w_rd;
  wire [15:0] w_imm = IfId_ir[15:0];
  wire [31:0] w_imm32 = {{16{w_imm[15]}}, w_imm};
  wire [31:0] w_rrs_fw = (MeWb_w && MeWb_rd2 == w_rs) ? w_rslt2 : w_rrs;
  wire [31:0] w_rrt_fw = (MeWb_w && MeWb_rd2 == w_rt) ? w_rslt2 : w_rrt;
  wire [31:0] w_rrt2 = (w_op>6'h5) ? w_imm32 : w_rrt_fw;
  wire [31:0] w_bop1 = (ExMe_w && ExMe_rd2 == w_rs) ? ExMe_rslt :
                       (MeWb_w && MeWb_rd2 == w_rs) ? w_rslt2 : w_rrs;
  wire [31:0] w_bop2 = (ExMe_w && ExMe_rd2 == w_rt) ? ExMe_rslt :
                       (MeWb_w && MeWb_rd2 == w_rt) ? MeWb_rslt : w_rrt;
  wire w_id_interlock = w_be && (IdEx_w && (IdEx_rd2 == w_rs || IdEx_rd2 == w_rt));
  wire w_pr_fail = w_be && (w_taken ? w_tpc : IfId_pc4) != r_pc;
  reg  r_pr_fail = 0;
  assign w_be = w_op==`BNE || w_op==`BEQ;
  assign w_tpc = IfId_pc4 + {w_imm32[29:0], 2'h0};
  assign w_taken = (w_op==`BNE && w_bop1!=w_bop2) || (w_op==`BEQ && w_bop1==w_bop2);
  m_predictor m_brp (w_clk, IfId_pc[12:2], (w_taken) ? w_tpc[12:2] : IfId_pc4[12:2], w_be && !w_id_interlock, r_pc[12:2], w_pr, w_pre);
  m_regfile m_regs (w_clk, w_rs, w_rt, MeWb_rd2, MeWb_w, w_rslt2, w_rrs, w_rrt);
  always @(posedge w_clk) begin
    r_pr_fail <= #3 w_pr_fail;
    IdEx_pc <= #3 IfId_pc;
    IdEx_op <= #3 w_op;
    IdEx_rs <= #3 w_rs;
    IdEx_rt <= #3 w_rt;
    IdEx_rd2 <= #3 w_rd2;
    IdEx_w <= #3 r_pr_fail ? 0 : (w_op==0 || (w_op>6'h5 && w_op<6'h28));
    IdEx_we <= #3 r_pr_fail ? 0 : (w_op>6'h27);
    IdEx_rrs <= #3 w_rrs_fw;
    IdEx_rrt <= #3 w_rrt_fw;
    IdEx_rrt2 <= #3 w_rrt2;
  end

  /**************************** EX stage ***********************************/
  wire [31:0] w_op1 = (ExMe_w && ExMe_rd2 == IdEx_rs) ? ExMe_rslt : 
                      (MeWb_w && MeWb_rd2 == IdEx_rs) ? w_rslt2 : IdEx_rrs;
  wire [31:0] w_op2 = (ExMe_w && IdEx_op == 0 && ExMe_rd2 == IdEx_rt) ? ExMe_rslt :
                      (MeWb_w && IdEx_op == 0 && MeWb_rd2 == IdEx_rt) ? w_rslt2 : IdEx_rrt2;
  wire [31:0] #10 w_rslt = w_op1 + w_op2; // ALU
  always @(posedge w_clk) begin
    ExMe_pc <= #3 IdEx_pc;
    ExMe_op <= #3 IdEx_op;
    ExMe_rt <= #3 IdEx_rt;
    ExMe_rd2 <= #3 IdEx_rd2;
    ExMe_w <= #3 IdEx_w;
    ExMe_we <= #3 IdEx_we;
    ExMe_rslt <= #3 w_rslt;
    ExMe_rrt <= #3 (MeWb_w && MeWb_rd2 == IdEx_rt) ? w_rslt2 : IdEx_rrt;
  end
  /**************************** MEM stage **********************************/
  // ホントはw_rslt2じゃなくてMeWb_rsltをフォワードしても良い(lw $xの直後にsw $xが来ないなら)
  wire [31:0] w_std = (ExMe_rt == MeWb_rd2) ? w_rslt2 : ExMe_rrt;
  m_memory m_dmem (w_clk, ExMe_rslt[12:2], ExMe_we, w_std, MeWb_ldd);
  always @(posedge w_clk) begin
    MeWb_pc <= #3 ExMe_pc;
    MeWb_rslt <= #3 ExMe_rslt;
    MeWb_op <= #3 ExMe_op;
    MeWb_rd2 <= #3 ExMe_rd2;
    MeWb_w <= #3 ExMe_w;
  end
  /**************************** WB stage ***********************************/
  assign w_rslt2 = (MeWb_op>6'h19 && MeWb_op<6'h28) ? MeWb_ldd : MeWb_rslt;
  /*************************************************************************/
  initial r_rout = 0;
  reg [31:0] r_tmp=0;
  always @(posedge w_clk) r_tmp <= (w_rst) ? 0 : (MeWb_rd2==30) ? w_rslt2 : r_tmp;
  always @(posedge w_clk) r_rout <= r_tmp;
endmodule


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
   initial #20000 $finish;
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
`include "program_interlock.txt"
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
  input  wire [10:0] w_baddr;
  input  wire        w_br, w_be;
  input  wire [10:0] w_paddr;
  output wire        w_pr;
  output wire        w_pre;

  reg [10:0] r_addr[0:1];
  reg        r_priority[0:1];
  reg [1:0]  r_predict[0:1];
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
  wire [1:0] w_pselect = (r_addr[0] == w_paddr) ? 0
                       : (r_addr[1] == w_paddr) ? 1
                       : 2;
  wire [1:0] w_npd = r_predict[w_bselect[0]][1] == w_br ? {w_br, w_br} :
                     (r_predict[w_bselect[0]] + (w_br ? 1 : -1));
  
  // update table
  always @(posedge w_clk) if (w_be == 1) begin
    if (w_bselect != 2) begin
      r_predict[w_bselect[0]] <= #3 w_npd;
      $write("Update prediction: pc=%x, br=%b, pr=%b\n", w_baddr, w_br, w_npd);
      // update priority
      r_priority[0] <= #3 (w_bselect == 0) ? 0 : 1;
      r_priority[1] <= #3 (w_bselect == 1) ? 0 : 1;
    end
    else begin
      if (r_priority[0] == 1) begin
        r_addr[0] <= #3 w_baddr;
        r_predict[0] <= #3 w_br ? 2'b10 : 2'b01;
        $write("Init prediction: slot=0, pc=%x, br=%b, pr=%b\n", w_baddr, w_br, w_br ? 2'b10 : 2'b01);
      end
      if (r_priority[1] == 1) begin
        r_addr[1] <= #3 w_baddr;
        r_predict[1] <= #3 w_br ? 2'b10 : 2'b01;
        $write("Init prediction: slot=1, pc=%x, br=%b, pr=%b\n", w_baddr, w_br, w_br ? 2'b10 : 2'b01);
      end
      // update priority
      r_priority[0] <= #3 (r_priority[0] == 1) ? 0 : 1;
      r_priority[1] <= #3 (r_priority[1] == 1) ? 0 : 1;
    end
  end

  // fetch prediction
  assign w_pr = r_predict[w_pselect[0]][1];
  assign w_pre = w_pselect != 2;
endmodule

module m_id_cache(w_clk, w_wkey, w_wvalue, w_we, w_rkey, w_rvalue);
  input wire w_clk;
  input wire [10:0] w_wkey, w_wvalue;
  input wire w_we;
  input wire [10:0] w_rkey;
  output wire [10:0] w_rvalue;
  
  reg [10:0] r_key[0:1];
  reg        r_priority[0:1];
  reg [10:0] r_value[0:1];
  generate genvar g;
    for (g = 0; g < 2; g = g + 1) begin : Gen
      initial r_key[g] = 11'b11111111111;
      initial r_priority[g] = g;
      initial r_value[g] = 0;
    end
  endgenerate
  
  wire [1:0] w_wselect = (r_key[0] == w_wkey) ? 0 :
                         (r_key[1] == w_wkey) ? 1 : 2;
  wire [1:0] w_rselect = (r_key[0] == w_rkey) ? 0 :
                         (r_key[1] == w_rkey) ? 1 : 2;
  
  wire w_prior1 = r_priority[0];
  wire w_prior2 = r_priority[1];
  
  // update table
  always @(posedge w_clk) if (w_we == 1) begin
    if (w_wselect != 2) begin
      r_value[w_wselect] <= #3 w_wvalue;
      // update priority
      r_priority[0] <= #3 (w_wselect == 0) ? 0 : 1;
      r_priority[1] <= #3 (w_wselect == 1) ? 0 : 1;
    end
    else begin
      if (r_priority[0] == 1) begin
        r_key[0] <= #3 w_wkey;
        r_value[0] <= #3 w_wvalue;
        $write("Init cache: slot=0, key=%x, val=%x\n", w_wkey, w_wvalue);
      end
      if (r_priority[1] == 1) begin
        r_key[1] <= #3 w_wkey;
        r_value[1] <= #3 w_wvalue;
        $write("Init cache: slot=1, key=%x, val=%x\n", w_wkey, w_wvalue);
      end
      // update priority
      r_priority[0] <= #3 (r_priority[0] == 1) ? 0 : 1;
      r_priority[1] <= #3 (r_priority[1] == 1) ? 0 : 1;
    end
  end
  
  // fetch value
  assign w_rvalue = r_value[w_rselect[0]];
endmodule

module m_proc11 (w_clk, r_rout);
  input wire w_clk;
  output reg [31:0] r_rout;

  reg r_halt = 0;
  wire w_be;
  wire w_rst = 0;
  wire w_interlock;
  reg [10:0] IfId_pc4=0, IdEx_pc4=0; // pipe regs
  reg [31:0] IdEx_rrs=0, IdEx_rrt=0, IdEx_rrt2=0; //
  reg [31:0] ExMe_rslt=0, ExMe_rrt=0; //
  reg [31:0] MeWb_rslt=0; //
  reg [5:0] IdEx_op=0, ExMe_op=0, MeWb_op=0; //
  reg [10:0] IfId_pc=0, IdEx_pc=0, ExMe_pc=0, MeWb_pc=0; //
  reg [10:0] IdEx_tpc=0;
  reg [4:0] IdEx_rs=0;
  reg [4:0] IdEx_rt=0, ExMe_rt=0;
  reg [4:0] IfId_rd2=0, IdEx_rd2=0, ExMe_rd2=0, MeWb_rd2=0;//
  reg IfId_w=0, IdEx_w=0, ExMe_w=0, MeWb_w=0; //
  reg IfId_we=0, IdEx_we=0, ExMe_we=0; //
  reg IfId_pr=0, IdEx_pr=0;
  wire [31:0] IfId_ir, MeWb_ldd; // note
  /**************************** IF stage **********************************/
  wire [10:0] w_bra;
  wire w_taken, w_pre, w_pr;
  wire [10:0] w_tpc, w_npc;
  wire [31:0] w_ir;
  reg [10:0] r_pc = 0; 
  wire [10:0] w_pc4 = r_pc + 1;
  m_memory m_imem (w_clk, r_pc, 1'd0, 32'd0, w_ir);
  assign w_npc = (w_rst | r_halt) ? 0 :
                 (w_pre) ? (w_pr ? w_bra : w_pc4) :
                 (w_pr_fail && w_taken) ? IdEx_tpc :
                 (w_pr_fail) ? IdEx_pc4 : w_pc4;
  assign IfId_ir = w_ir;
  always @(posedge w_clk) if (!w_interlock) begin
    r_pc <= #3 w_npc;
    IfId_pc <= #3 r_pc;
    IfId_pc4 <= #3 w_pc4;
    IfId_pr <= #3 w_pre && w_pr;
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
  // assign w_be = w_op==`BNE || w_op==`BEQ;
  assign w_be = w_op[2];
  assign w_tpc = IfId_pc4 + w_imm[10:0];

  m_regfile m_regs (w_clk, w_rs, w_rt, MeWb_rd2, MeWb_w, w_rslt2, w_rrs, w_rrt);
  always @(posedge w_clk) if (!w_interlock) begin
    IdEx_pc <= #3 IfId_pc;
    IdEx_pc4 <= #3 IfId_pc4;
    IdEx_op <= #3 r_pr_fail ? {w_op[5:3], 1'b0, w_op[1:0]} : w_op;
    IdEx_rs <= #3 w_rs;
    IdEx_rt <= #3 w_rt;
    IdEx_rd2 <= #3 w_rd2;
    IdEx_w <= #3 r_pr_fail ? 0 : (w_op==0 || (w_op>6'h5 && w_op<6'h28));
    IdEx_we <= #3 r_pr_fail ? 0 : (w_op>6'h27);
    IdEx_rrs <= #3 w_rrs_fw;
    IdEx_rrt <= #3 w_rrt_fw;
    IdEx_rrt2 <= #3 w_rrt2;
    IdEx_tpc <= #3 w_tpc;
    IdEx_pr <= #3 IfId_pr;
  end

  /**************************** EX stage ***********************************/
  wire [31:0] w_op1 = (ExMe_w && ExMe_rd2 == IdEx_rs) ? ExMe_rslt : 
                      (MeWb_w && MeWb_rd2 == IdEx_rs) ? MeWb_rslt : IdEx_rrs;
  wire [31:0] w_op2 = (ExMe_w && IdEx_op == 0 && ExMe_rd2 == IdEx_rt) ? ExMe_rslt :
                      (MeWb_w && IdEx_op == 0 && MeWb_rd2 == IdEx_rt) ? MeWb_rslt : IdEx_rrt2;
  wire [31:0] #10 w_rslt = w_op1 + w_op2; // ALU
  
  assign w_interlock = (w_ex_be || IdEx_w || IdEx_we) && MeWb_w && (MeWb_rd2 == IdEx_rs || (IdEx_op == 0 && MeWb_rd2 == IdEx_rt)) && w_load_mem;
  
  // branch
  // w_op[2] populates only if op == BNE || op == BEQ
  wire w_ex_be = !r_pr_fail && IdEx_op[2];
  assign w_taken = w_ex_be && (IdEx_op[0] ? w_op1!=w_op2 : w_op1==w_op2);
  wire w_pr_fail = w_ex_be && w_taken != IdEx_pr;
  reg r_pr_fail = 0;
  m_predictor m_brp (w_clk, IdEx_pc, w_taken, w_ex_be, r_pc, w_pr, w_pre);
  m_id_cache m_br_cache (w_clk, IdEx_pc, IdEx_tpc, w_ex_be, r_pc, w_bra);
  
  always @(posedge w_clk) if (!w_interlock) begin
    r_pr_fail <= #3 w_pr_fail;
    ExMe_pc <= #3 IdEx_pc;
    ExMe_op <= #3 IdEx_op;
    ExMe_rt <= #3 IdEx_rt;
    ExMe_rd2 <= #3 IdEx_rd2;
    ExMe_w <= #3 r_pr_fail ? 0 : IdEx_w;
    ExMe_we <= #3 r_pr_fail ? 0 : IdEx_we;
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
  wire w_load_mem = (MeWb_op>6'h19 && MeWb_op<6'h28);
  assign w_rslt2 = w_load_mem ? MeWb_ldd : MeWb_rslt;
  /*************************************************************************/
  initial r_rout = 0;
  reg [31:0] r_tmp=0;
  always @(posedge w_clk) r_tmp <= (w_rst) ? 0 : (MeWb_rd2==30) ? w_rslt2 : r_tmp;
  always @(posedge w_clk) r_rout <= r_tmp;
endmodule


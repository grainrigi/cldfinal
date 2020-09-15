/**************************************************************************/
/* code130.v                          For CSC.T341 CLD Archlab TOKYO TECH */
/**************************************************************************/
`timescale 1ns/100ps
`default_nettype none

`define BEQ 6'h4
`define BNE 6'h5
`define SLLV 6'h4
`define SRLV 6'h6
`define NOP 32'h20
`define HALT {6'h4, 5'd0, 5'd0, 16'hffff}

`ifdef IVERILOG
/***** top module for simulation *****/
module m_top (); 
   reg r_clk=0; initial forever #50 r_clk = ~r_clk;
   reg r_clk2=1; initial forever #25 r_clk2 = ~r_clk2;
   wire [31:0] w_led;

   initial $dumpfile("main.vcd");
   initial $dumpvars(0, m_top);

   m_proc_sc p (r_clk, r_clk2, w_led);
   /*
   initial $write("time: s r_pc     w_ir     w_rrs    w_rrt2   r_rslt2  r_led\n");
   always@(posedge r_clk) $write("%4d: %d %x %x %x %x %x %x\n", $time,
                         p.r_state, p.r_pc, p.w_ir, p.w_rrs, p.w_rrt2, p.w_rslt2, w_led);
                      */
   initial #14000 $finish;
endmodule

`elsif CONTEST_V
/***** top module for verification *****/
module m_top ();
  reg r_clk=0; initial forever #50 r_clk = ~r_clk;
  wire [31:0] w_led;
  m_proc11 p (r_clk, w_led);
  always@(posedge r_clk)
  if(p.MeWb_w) $write("%08x\n", p.w_rslt2);
  always@(posedge r_clk) if(p.IfId_ir==`HALT) #200 $finish();
endmodule

`elsif CONTEST
module m_top ();
  reg r_clk=0; initial forever #50 r_clk = ~r_clk;
  wire [31:0] w_led;
  reg [31:0] r_cnt = 0;
  always@(posedge r_clk) r_cnt <= r_cnt + 1;
  m_proc11 p (r_clk, w_led);
  initial $write("clock : r_pc w_ir w_rrs w_rrt2 r_rslt2 r_led\n");
  always@(posedge r_clk) begin
    $write("%6d: %x %x %x %x %x %x ", r_cnt,
      p.r_pc, p.IfId_ir, p.w_rrs, p.w_rrt2,
      p.w_rslt2, w_led);
    if(p.w_op == 0 && p.w_funct == 6'h20) $write("add");
    if(p.w_op == 0 && p.w_funct == `SLLV) $write("sllv");
    if(p.w_op == 0 && p.w_funct == `SRLV) $write("srlv");
    if(p.w_op == 6'h8) $write("addi");
    if(p.w_op == 6'h23) $write("lw");
    if(p.w_op == 6'h2b) $write("sw");
    if(p.w_op == `BEQ) $write("beq");
    if(p.w_op == `BNE) $write("bne");
    $write("\n");
  end
  always@(posedge r_clk) if(p.IfId_ir==`HALT) #210 $finish();
endmodule
`else
/***** main module for FPGA implementation *****/
module m_main (w_clk, w_led);
   input  wire w_clk;
   output wire [3:0] w_led;
 
   wire w_clk2, w_clk2_, w_locked;
   clk_wiz_0 clk_w0 (w_clk2, w_clk2_, 0, w_locked, w_clk);
   
   wire [31:0] w_dout;
   m_proc_sc p (w_clk2, w_clk2_, w_dout);

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
`include "program_shift.txt"
endmodule

module m_memory2 (
  w_clk,
  w_aaddr, w_awe, w_adin, r_adout,
  w_baddr, w_bwe, w_bdin, r_bdout
);
  input  wire w_clk, w_awe, w_bwe;
  input  wire [10:0] w_aaddr, w_baddr;
  input  wire [31:0] w_adin, w_bdin;
  output reg [31:0] r_adout = 0, r_bdout;
  reg [31:0] 	      cm_ram [0:2047]; // 4K word (2048 x 32bit) memory
  always @(posedge w_clk) if (w_awe) cm_ram[w_aaddr] <= w_adin;
  always @(posedge w_clk) if (w_bwe) cm_ram[w_baddr] <= w_bdin;
  always @(posedge w_clk) r_adout <= cm_ram[w_aaddr];
  always @(posedge w_clk) r_bdout <= cm_ram[w_baddr];
`include "program_contest.txt"
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

endmodule

module m_regfile2 (
  w_clk, w_clk2,
  w_arr1, w_arr2, w_awr, w_awe, w_awdata, w_ardata1, w_ardata2,
  w_brr1, w_brr2, w_bwr, w_bwe, w_bwdata, w_brdata1, w_brdata2
);
  input  wire        w_clk, w_clk2;
  input  wire [4:0]  w_arr1, w_arr2, w_awr, w_brr1, w_brr2, w_bwr;
  input  wire [31:0] w_awdata, w_bwdata;
  input  wire        w_awe, w_bwe;
  output wire [31:0] w_ardata1, w_ardata2, w_brdata1, w_brdata2;
  
  reg [31:0] ra[0:31], rb[0:31];
  assign w_ardata1 = (w_arr1==0) ? 0 : ra[w_arr1];
  assign w_ardata2 = (w_arr2==0) ? 0 : ra[w_arr2];
  assign w_brdata1 = (w_brr1==0) ? 0 : rb[w_brr1];
  assign w_brdata2 = (w_brr2==0) ? 0 : rb[w_brr2];
  
  wire [4:0] w_wr = w_clk ? w_awr : w_bwr;
  wire w_we = (w_clk && w_awe) || (!w_clk && w_bwe);
  wire [31:0] w_wdata = w_clk ? w_awr : w_bwr;
  always @(posedge w_clk2) if (w_we) begin
    ra[w_wr] <= w_wdata;
    rb[w_wr] <= w_wdata;
  end
endmodule

/**** 分岐予測器
 過去の分岐結果を保存し、その結果に基づくw_takenの予測を次回の分岐時に提供します。

 * ワイヤの役割
   * 分岐結果保存用
     w_baddr 分岐命令のアドレス
     w_br    分岐したかどうか(w_taken)
     w_bdst  分岐先アドレス
     w_be    分岐結果の保存を次回のposedgeで行うかどうか
   * 予測取得用
     w_paddr 予測したい命令のアドレス
     w_pre   予測を提供できるかどうか
     w_pr    予測結果(w_taken)
     w_pdst  予測した命令の分岐先アドレス
  
  * 予測結果の取得に関して
    分岐予測が必要となる状況をまず考えましょう。

    まず、r_pcが分岐命令を指しているとき、
    w_npcは分岐先の最初の命令を指していることが望ましいです。
    よって、分岐予測を提供する必要があるのはr_pcが分岐命令を指しているときです。

    よって、w_paddrにはr_pcを供給します。
    このとき、分岐結果が保存されていれば、
    w_preは1となり、
    w_prは分岐をtakeするべきかどうか、
    w_pdstにw_tpcの値が供給されます。
    よって、w_npcにはw_prの値に応じてw_pdst(taken)またはw_pc4(not taken)を供給します。

    続いて、予測結果の正しさについて検証する必要が有ります。
    分岐判定はEXステージで行われるので、正しさが判明するのは上述の状態から2サイクル後です。

    w_prの値をIFステージからEXステージまで伝播させます(w_pr -> IfId_pr -> IdEx_pr)。
    これにより、w_takenとIdEx_prを比較すれば予測の成否がわかります。

    予測が失敗していれば直ちに正しい分岐先をさすように修正しなければなりません。
    本来の分岐先は、IdEx_tpc(taken), IdEx_pc4(not taken)となります。
    予測が失敗した場合w_npcに上述の値を供給します。

    なお、予測が失敗した場合、2サイクルストールします。
    IDステージには実行する必要のない命令が供給されており、
    IFステージでもr_pcが実行する必要のない命令を指してしまっているからです。
    これら2命令に関して、レジスタとメモリへの書き込みを無効化してnop化する必要が有ります。
    (さらに、無効な分岐命令がnpcに干渉しないようにw_opも変更すべきです)

  * 分岐履歴の保存について
    分岐履歴キャッシュは4-wayのLRUキャッシュで、
    履歴自体は2ビットの飽和カウンタで記録されます。

    分岐情報は以下の4状態に分けられます。

    11: Strongly Taken
    10: Weakly Taken
    01: Weakly Not Taken
    00: Strongly Not Taken

    一度の分岐結果の供給ではこの状態を上または下に1つまでしか移動できません。
    よって、何回も分岐が連続でtakenとなっていれば、
    一回not takenになったとしても次の予測結果がすぐにはnot takenに転じることはありません。

    先述の通り、履歴保存スロットは4スロットです。
    履歴には、分岐命令の位置するアドレス、分岐情報、分岐先アドレスが保存されています。
    分岐先アドレスを保存するのはIFステージで(命令のデコード前に)分岐先を決定しなければならないからです。
    スロットがいっぱいになった場合、もっとも昔に書き込まれたスロットの内容が上書きされます。
*/
module m_predictor (w_clk, w_baddr, w_br, w_bdst, w_be, w_paddr, w_pr, w_pdst, w_pre);
  input  wire        w_clk;
  input  wire [10:0] w_baddr, w_bdst;
  input  wire        w_br, w_be;
  input  wire [10:0] w_paddr;
  output wire        w_pr;
  output wire [10:0] w_pdst;
  output wire        w_pre;

  // 履歴の保存領域
  reg [10:0] r_addr[0:3];     // 分岐元アドレス(キャッシュのキー)
  reg [1:0]  r_priority[0:3]; // 各スロットの優先度(0が一番高く、3ならば次の新規書き込みで破棄)
  reg [10:0] r_dst[0:3];      // 分岐先アドレス
  reg [1:0]  r_predict[0:3];  // 分岐情報(2ビット飽和カウンタ)
  generate genvar g;
    for (g = 0; g < 4; g = g + 1) begin : Gen
      // 変に反応しないように無効な値を入れておく
      initial r_addr[g] = 11'b11111111111;
      // 優先度が最初から振られてないと誤動作するので
      initial r_priority[g] = g;
      initial r_dst[g] = 11'b11111111111;
      initial r_predict[g] = 0;
    end
  endgenerate

  // 保存先の選択：既にエントリがあればそのインデックス、なければ4
  wire [2:0] w_bselect = (r_addr[0] == w_baddr) ? 0
                       : (r_addr[1] == w_baddr) ? 1
                       : (r_addr[2] == w_baddr) ? 2
                       : (r_addr[3] == w_baddr) ? 3
                       : 4;
  // 2ビット幅に縮めたバージョン(selector effective)
  wire [1:0] w_bselect_e = w_bselect[1:0];
  // 選択された保存先の優先度
  wire [1:0] w_bpriority = r_priority[w_bselect_e];
  // 予測の読み込み元の選択：エントリがヒットすればそのインデックス、なければ4
  wire [2:0] w_pselect = (r_addr[0] == w_paddr) ? 0
                       : (r_addr[1] == w_paddr) ? 1
                       : (r_addr[2] == w_paddr) ? 2
                       : (r_addr[3] == w_paddr) ? 3
                       : 4;
  wire [1:0] w_pselect_e = w_pselect[1:0];
  // 供給された分岐結果を既存の分岐情報に足し込んだ結果(飽和カウンタ)
  wire [1:0] w_npd = r_predict[w_bselect_e][1] == w_br ? {w_br, w_br} :
                     (r_predict[w_bselect_e] + (w_br ? 1 : -1));
  
  
  // update prediction
  always @(posedge w_clk) if (w_be == 1) begin
    if (w_bselect != 4) begin
      // update priority
      // $write("Update prediction: pc=%x, br=%b, pr=%b\n", w_baddr, w_br, w_npd);
    end
  end
  
  generate genvar g2;
    for (g2 = 0; g2 < 4; g2 = g2 + 1) begin : Gen2
      // 分岐結果の保存処理(w_beが1のときのみ)
      always @(posedge w_clk) if (w_be == 1) begin
        if (w_bselect != 4) begin
          // 過去に分岐情報が保存されているので、それを更新
          // bselectで選択されたスロットならば分岐情報をw_npdで更新する
          r_predict[g2] <= #3 w_bselect_e == g2 ? w_npd : r_predict[g2];
          // 優先度を正しく更新(bselectで選択されたスロットを0にして、それ以外は必要に応じて優先度を増加)
          r_priority[g2] <= #3 (w_bselect_e == g2) ? 0 :
                              (r_priority[g2] < w_bpriority) ? r_priority[g2] + 1 : r_priority[g2];
        end else
          // 分岐情報を新たに書き込む
          if (r_priority[g2] == 3) begin
            // priorityが3のスロットの場合、最も古い情報なので上書き
            r_addr[g2] <= #3 w_baddr;
            r_dst[g2] <= #3 w_bdst;
            r_predict[g2] <= #3 w_br ? 2'b10 : 2'b01;
            // $write("Init prediction: slot=%d, pc=%x, br=%b, pr=%b\n", g2, w_baddr, w_br, w_br ? 2'b10 : 2'b01);
          end
          // 優先度は新たに書き込んだスロットが0、それ以外は1増加
          r_priority[g2] <= #3 (r_priority[g2] == 3) ? 0 : r_priority[g2] + 1;
        end
      end
  endgenerate
  
  // 予測結果の供給(非同期)
  assign w_pr = r_predict[w_pselect_e][1];
  assign w_pdst = r_dst[w_pselect_e];
  assign w_pre = w_pselect != 4;
  
  always @(posedge w_clk) if (w_pre) begin
    //$write("Provide prediction: pc=%x, br=%b, dst=%x\n", w_paddr, w_pr, w_pdst);
  end
endmodule

module m_proc_sc (w_clk, w_clk2, r_rout);
  input wire w_clk, w_clk2;
  output reg [31:0] r_rout;
  
  /**************************** IF stage **********************************/
  reg [10:0] r_pc1=0, r_pc2=1;
  wire [10:0] w_pc41 = r_pc1+2, w_pc42 = r_pc2+2;
  wire [31:0] w_ir1, w_ir2;
  
  m_memory2 m_imem (
    w_clk,
    r_pc1, 1'd0, 32'd0, w_ir1,
    r_pc2, 1'd0, 32'd0, w_ir2
  );
  
  always @(posedge w_clk) begin
    r_pc1 <= #3 r_pc1 + 2;
    r_pc2 <= #3 r_pc2 + 2;
  end
  
  /**************************** regs **********************************/
  wire [4:0] w_rr11, w_rr21, w_wr1, w_rr12, w_rr22, w_wr2;
  wire w_we1, w_we2;
  wire [31:0] w_rdata11, w_rdata21, w_wdata1, w_rdata12, w_rdata22, w_wdata2;
  m_regfile2 m_regs (
    w_clk, w_clk2,
    w_rr11, w_rr21, w_wr1, w_we1, w_wdata1, w_rdata11, w_rdata21,
    w_rr12, w_rr22, w_wr2, w_we2, w_wdata2, w_rdata12, w_rdata22
  );
  
  /**************************** dmem **********************************/
  wire [10:0] w_mem_addr1, w_mem_addr2;
  wire [31:0] w_mem_wdata1, w_mem_rdata1, w_mem_wdata2, w_mem_rdata2;
  wire w_mem_we1, w_mem_we2;
  m_memory2 m_dmem (
    w_clk,
    w_mem_addr1, w_mem_we1, w_mem_wdata1, w_mem_rdata1,
    w_mem_addr2, w_mem_we2, w_mem_wdata2, w_mem_rdata2
  );
  
  /**************************** pipelines **********************************/
  wire [4:0] w_Ex_rd21, w_Ex_rd22;
  wire w_interlock1, w_interlock2;
  m_pipe m_p1 (
    w_clk,
    r_pc1, w_pc41, 1'd0, 1'd0, w_ir1,
    w_rr11, w_rr21, w_wr1, w_wdata1, w_we1, w_rdata11, w_rdata21,
    w_Ex_rd22, w_Ex_rd21, w_interlock1,
    w_mem_addr1, w_mem_wdata1, w_mem_we1, w_mem_rdata1,
    1'd0, 5'd0
  );
  m_pipe m_p2 (
    w_clk,
    r_pc2, w_pc42, 1'd0, 1'd0, w_ir2,
    w_rr12, w_rr22, w_wr2, w_wdata2, w_we2, w_rdata12, w_rdata22,
    w_Ex_rd21, w_Ex_rd22, w_interlock2,
    w_mem_addr2, w_mem_wdata2, w_mem_we2, w_mem_rdata2,
    1'd0, 5'd0
  );
  
  /*************************************************************************/
  initial r_rout = 0;
  reg [31:0] r_tmp=0;
  always @(posedge w_clk) begin
    if (w_we1 && w_wr1 == 30)
      r_tmp <= w_wdata1;
    else if (w_we2 && w_wr2 == 30)
      r_tmp <= w_wdata2;
  end
  always @(posedge w_clk) r_rout <= r_tmp;
endmodule

module m_pipe (
  w_clk,
  i_pc, i_pc4, i_pre, i_pr, i_ir,
  o_rr1, o_rr2, o_wr, o_wdata, o_we, i_rdata1, i_rdata2,
  i_Ex_rd2, o_Ex_rd2, o_interlock,
  o_mem_addr, o_mem_wdata, o_mem_we, i_mem_rdata,
  i_Wb_w, i_Wb_rd2
);
  input  wire w_clk;
  
  input  wire [10:0] i_pc, i_pc4;
  input  wire i_pre, i_pr;
  input  wire [31:0] i_ir;
  
  output wire [4:0] o_rr1, o_rr2, o_wr;
  output wire [31:0] o_wdata;
  output wire o_we;
  input  wire [31:0] i_rdata1, i_rdata2;
  
  input  wire [4:0] i_Ex_rd2;
  output wire [4:0] o_Ex_rd2;
  output wire o_interlock;
  
  output wire [10:0] o_mem_addr;
  output wire [31:0] o_mem_wdata;
  output wire o_mem_we;
  input  wire [31:0] i_mem_rdata;
  
  input wire i_Wb_w;
  input wire [4:0] i_Wb_rd2; 
  
  reg r_halt = 0;
  wire w_rst = 0;
  wire w_interlock; // パイプラインをインターロック(停止)するかどうか (IF,ID,EXが停止、MEM,WBは稼働する)
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
  reg IdEx_w=0, ExMe_w=0, MeWb_w=0; //
  reg IdEx_we=0, ExMe_we=0; //
  reg IfId_pr=0, IdEx_pr=0;
  reg IdEx_rsfwme=0, IdEx_rsfwwb=0, IdEx_rtfwme=0, IdEx_rtfwwb=0; // EXステージでデータフォワードが必要かどうかのフラグ
  reg [5:0] IdEx_funct=0;
  wire [31:0] IfId_ir, MeWb_ldd; // note
  /**************************** IF stage (external) **********************************/
  wire [10:0] w_bra; // 分岐予測器から供給されたtaken時の分岐先アドレス
  wire w_taken; // EXステージで判定した分岐結果
  assign IfId_ir = i_ir;
  always @(posedge w_clk) if (!w_interlock) begin
    IfId_pc <= #3 i_pc;
    IfId_pc4 <= #3 i_pc4;
    IfId_pr <= #3 i_pre && i_pr;
  end
  
  /**************************** ID stage ***********************************/
  wire [31:0] w_rrs, w_rrt, w_rslt2;
  wire [5:0] w_op = IfId_ir[31:26];
  wire [4:0] w_rs = IfId_ir[25:21];
  wire [4:0] w_rt = IfId_ir[20:16];
  wire [4:0] w_rd = IfId_ir[15:11];
  wire [4:0] w_rd2 = (w_op!=0) ? w_rt : w_rd;
  wire [5:0] w_funct = IfId_ir[5:0];
  wire [15:0] w_imm = IfId_ir[15:0];
  wire [31:0] w_imm32 = {{16{w_imm[15]}}, w_imm};
  wire [31:0] w_rrs_fw = (MeWb_w && MeWb_rd2 == w_rs) ? w_rslt2 : w_rrs;
  wire [31:0] w_rrt_fw = (MeWb_w && MeWb_rd2 == w_rt) ? w_rslt2 : w_rrt;
  wire [31:0] w_rrt2 = (w_op>6'h5) ? w_imm32 : w_rrt_fw;
  wire [10:0] w_tpc = IfId_pc4 + w_imm[10:0];

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
    // MEM, WBからのフォワーディングの必要性を判定
    IdEx_rsfwme <= #3 IdEx_w && IdEx_rd2 == w_rs;
    IdEx_rsfwwb <= #3 ExMe_w && ExMe_rd2 == w_rs;
    // rtはRフォーマット(w_op == 0)の場合のみ必要
    IdEx_rtfwme <= #3 IdEx_op == 0 && !w_pr_fail && IdEx_w && IdEx_rd2 == w_rt;
    IdEx_rtfwwb <= #3 IdEx_op == 0 && ExMe_w && ExMe_rd2 == w_rt; 
    IdEx_funct <= #3 w_funct;
  end
  assign o_rr1 = w_rs;
  assign o_rr2 = w_rt;
  assign o_wr = MeWb_rd2;
  assign o_we = MeWb_w;
  assign o_wdata = w_rslt2;
  assign w_rrs = i_rdata1;
  assign w_rrt = i_rdata2;
  
  /**************************** EX stage ***********************************/
  // 必要に応じてフォワーディングする(WBからはw_rslt2でなくMeWb_rsltをフォワード(lwの結果はフォワードしない))
  wire [31:0] w_op1 = (IdEx_rsfwme) ? ExMe_rslt : 
                      (IdEx_rsfwwb) ? MeWb_rslt : IdEx_rrs;
  wire [31:0] w_op2 = (IdEx_rtfwme) ? ExMe_rslt :
                      (IdEx_rtfwwb) ? MeWb_rslt : IdEx_rrt2;

  // ALU
  wire [31:0] #10 w_rslt = (IdEx_op == 0 && IdEx_funct == `SLLV) ? w_op1 << w_op2[4:0] :
                           (IdEx_op == 0 && IdEx_funct == `SRLV) ? w_op1 >> w_op2[4:0] :
                           w_op1 + w_op2;
  
  wire w_fw_ldd = (w_ex_be || IdEx_w || IdEx_we) && MeWb_w && (MeWb_rd2 == IdEx_rs || (IdEx_op == 0 && MeWb_rd2 == IdEx_rt)) && w_load_mem;
  wire w_fw_ex = i_Ex_rd2 != 0 && (i_Ex_rd2 == IdEx_rs || i_Ex_rd2 == IdEx_rt);
  assign w_interlock = w_fw_ldd || w_fw_ex;
  
  // 分岐判定
  wire w_ex_be = !r_pr_fail && (IdEx_op == `BNE || IdEx_op == `BEQ);
  assign w_taken = w_ex_be && (IdEx_op == `BNE ? w_op1!=w_op2 : w_op1==w_op2);
  wire w_pr_fail = w_ex_be && w_taken != IdEx_pr;
  // r_pr_fail = 1 の場合、その時点で前2つの命令はNOP化しなければならない
  reg r_pr_fail = 0;
  
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
  assign o_Ex_rd2 = IdEx_w ? IdEx_rd2 : 0;
  assign o_interlock = w_interlock;
  
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
  assign o_mem_addr = ExMe_rslt[12:2];
  assign o_mem_wdata = w_std;
  assign o_mem_we = ExMe_we;
  assign MeWb_ldd = i_mem_rdata;
  
  /**************************** WB stage ***********************************/
  wire w_load_mem = (MeWb_op>6'h19 && MeWb_op<6'h28);
  assign w_rslt2 = w_load_mem ? MeWb_ldd : MeWb_rslt;
endmodule

`ifdef HOGE
module m_proc11 (w_clk, r_rout);
  input wire w_clk;
  output reg [31:0] r_rout;

  reg r_halt = 0;
  wire w_rst = 0;
  wire w_interlock; // パイプラインをインターロック(停止)するかどうか (IF,ID,EXが停止、MEM,WBは稼働する)
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
  reg IdEx_rsfwme=0, IdEx_rsfwwb=0, IdEx_rtfwme=0, IdEx_rtfwwb=0; // EXステージでデータフォワードが必要かどうかのフラグ
  reg [5:0] IdEx_funct=0;
  wire [31:0] IfId_ir, MeWb_ldd; // note
  /**************************** IF stage **********************************/
  wire [10:0] w_bra; // 分岐予測器から供給されたtaken時の分岐先アドレス
  wire w_taken, w_pre, w_pr; // w_taken: EXステージで判定した分岐結果, w_pre, w_pr: 分岐予測器より
  wire [10:0] w_npc;
  reg [10:0] r_pc = 0; 
  wire [10:0] w_pc4 = r_pc + 1;
  m_memory m_imem (w_clk, r_pc, 1'd0, 32'd0, IfId_ir);
  assign w_npc = (w_rst | r_halt) ? 0 :
                 (w_pre) ? (w_pr ? w_bra : w_pc4) :
                 (!w_pr_fail) ? w_pc4 :
                 (w_taken) ? IdEx_tpc : IdEx_pc4;
  always @(posedge w_clk) if (!w_interlock) begin
    r_pc <= #3 w_npc;
    IfId_pc <= #3 r_pc;
    IfId_pc4 <= #3 w_pc4;
    IfId_pr <= #3 w_pre && w_pr; // 分岐をどっちに予測したか(分岐予測が提供されればその結果、提供されなければ必ずnot takenと予測)
  end
  /**************************** ID stage ***********************************/
  wire [31:0] w_rrs, w_rrt, w_rslt2;
  wire [5:0] w_op = IfId_ir[31:26];
  wire [4:0] w_rs = IfId_ir[25:21];
  wire [4:0] w_rt = IfId_ir[20:16];
  wire [4:0] w_rd = IfId_ir[15:11];
  wire [4:0] w_rd2 = (w_op!=0) ? w_rt : w_rd;
  wire [5:0] w_funct = IfId_ir[5:0];
  wire [15:0] w_imm = IfId_ir[15:0];
  wire [31:0] w_imm32 = {{16{w_imm[15]}}, w_imm};
  wire [31:0] w_rrs_fw = (MeWb_w && MeWb_rd2 == w_rs) ? w_rslt2 : w_rrs;
  wire [31:0] w_rrt_fw = (MeWb_w && MeWb_rd2 == w_rt) ? w_rslt2 : w_rrt;
  wire [31:0] w_rrt2 = (w_op>6'h5) ? w_imm32 : w_rrt_fw;
  wire [10:0] w_tpc = IfId_pc4 + w_imm[10:0];

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
    // MEM, WBからのフォワーディングの必要性を判定
    IdEx_rsfwme <= #3 IdEx_w && IdEx_rd2 == w_rs;
    IdEx_rsfwwb <= #3 ExMe_w && ExMe_rd2 == w_rs;
    // rtはRフォーマット(w_op == 0)の場合のみ必要
    IdEx_rtfwme <= #3 w_op == 0 && !w_pr_fail && IdEx_w && IdEx_rd2 == w_rt;
    IdEx_rtfwwb <= #3 w_op == 0 && ExMe_w && ExMe_rd2 == w_rt; 
    IdEx_funct <= #3 w_funct;
  end

  /**************************** EX stage ***********************************/
  // 必要に応じてフォワーディングする(WBからはw_rslt2でなくMeWb_rsltをフォワード(lwの結果はフォワードしない))
  wire [31:0] w_op1 = (IdEx_rsfwme) ? ExMe_rslt : 
                      (IdEx_rsfwwb) ? MeWb_rslt : IdEx_rrs;
  wire [31:0] w_op2 = (IdEx_rtfwme) ? ExMe_rslt :
                      (IdEx_rtfwwb) ? MeWb_rslt : IdEx_rrt2;

  // ALU
  wire [31:0] #10 w_rslt = (IdEx_op == 0 && IdEx_funct == `SLLV) ? w_op1 << w_op2[4:0] :
                           (IdEx_op == 0 && IdEx_funct == `SRLV) ? w_op1 >> w_op2[4:0] :
                           w_op1 + w_op2;
  
  // WBからメモリの読み出し結果をフォワードしなければならない場合、インターロック
  assign w_interlock = (w_ex_be || IdEx_w || IdEx_we) && MeWb_w && (MeWb_rd2 == IdEx_rs || (IdEx_op == 0 && MeWb_rd2 == IdEx_rt)) && w_load_mem;
  
  // 分岐判定
  wire w_ex_be = !r_pr_fail && (IdEx_op == `BNE || IdEx_op == `BEQ);
  assign w_taken = w_ex_be && (IdEx_op == `BNE ? w_op1!=w_op2 : w_op1==w_op2);
  wire w_pr_fail = w_ex_be && w_taken != IdEx_pr; // 分岐に失敗したかどうか
  // r_pr_fail = 1 の場合、その時点でID, EXステージにある命令はNOP化しなければならない
  reg r_pr_fail = 0;
  m_predictor m_brp (w_clk, IdEx_pc, w_taken, IdEx_tpc, w_ex_be, r_pc, w_pr, w_bra, w_pre);
  
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
  always @(posedge w_clk) r_tmp <= (w_rst) ? 0 : (MeWb_w && MeWb_rd2==30) ? w_rslt2 : r_tmp;
  always @(posedge w_clk) r_rout <= r_tmp;
endmodule
`endif


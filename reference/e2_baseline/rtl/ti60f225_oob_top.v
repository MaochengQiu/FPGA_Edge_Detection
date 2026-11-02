
/////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2013-2021 Efinix Inc. All rights reserved.
//
// Description:
// Example top file for ti60f225 dev kit OOB design
//
// Language:  Verilog 2001
//Ti60f225_sc431hai2hdmi_v6：
//使用了最新版本的framebuffer_v3;
// ------------------------------------------------------------------------------

/////////////////////////////////////////////////////////////////////////////////
//`define SOFT_TAP 1
`include "ddr3_controller/ddr3_parameter.vh"
// `include "define.v"

module ti60f225_oob_top #(
    parameter E1_NMS_ENABLE = 1'b1, // E1 A/B: 1=NMS, 0=original Sobel decision.
    parameter E1_NMS_STRICT_TIES = 1'b0, // Keep equal maxima for curve continuity.

	parameter                       RANK_RATIO         = 1,       // # of unique CS outputs per rank
	parameter                       ASYN_AXI_CLK       = `ASYN_AXI_CLK, 
	parameter                       RANKS              = `RANKS,
	parameter                       CK_WIDTH           = `CK_WIDTH,       // # of CK/CK# outputs to memory   
	parameter                       CKE_WIDTH          = `CKE_WIDTH,       // # of cke outputs
	parameter                       CS_WIDTH           = `CS_WIDTH,       // # of unique CS outputs
	parameter                       BANK_WIDTH         = `BANK_WIDTH,       // # of bank bits
	parameter                       ROW_WIDTH          = `ROW_WIDTH,       // DRAM address bus width
	parameter                       COL_WIDTH          = `COL_WIDTH,      // column address width
	parameter                       DM_WIDTH           = `DM_WIDTH,       // # of DM (data mask)
	parameter                       DQS_WIDTH          = `DQS_WIDTH,       // # of DQS (strobe)
	parameter                       DQ_WIDTH           = `DQ_WIDTH,      // # of DQ (data)
	parameter                       ODT_WIDTH          = `ODT_WIDTH,
	parameter                       DQ_CNT_WIDTH       = `DQ_CNT_WIDTH,       // = ceil(log2(DQ_WIDTH))
	parameter                       DQS_CNT_WIDTH      = `DQS_CNT_WIDTH,       // = ceil(log2(DQS_WIDTH))  
	parameter                       DRAM_WIDTH         = `DRAM_WIDTH,       // # of DQ per DQS   
	parameter                       DATA_WIDTH         = `DATA_WIDTH,
	parameter                       ADDR_WIDTH         = `ADDR_WIDTH,    
	parameter                       AXI_ID_WIDTH       = `AXI_ID_WIDTH,
	parameter                       AXI_ADDR_WIDTH     = `AXI_ADDR_WIDTH,
	parameter                       AXI_DATA_WIDTH     = `AXI_DATA_WIDTH
)
(

  (* syn_peri_port = 0 *) input jtag_inst1_CAPTURE,
  (* syn_peri_port = 0 *) input jtag_inst1_DRCK,
  (* syn_peri_port = 0 *) input jtag_inst1_RESET,
  (* syn_peri_port = 0 *) input jtag_inst1_RUNTEST,
  (* syn_peri_port = 0 *) input jtag_inst1_SEL,
  (* syn_peri_port = 0 *) input jtag_inst1_SHIFT,
  (* syn_peri_port = 0 *) input jtag_inst1_TCK,
  (* syn_peri_port = 0 *) input jtag_inst1_TDI,
  (* syn_peri_port = 0 *) input jtag_inst1_TMS,
  (* syn_peri_port = 0 *) input jtag_inst1_UPDATE,
  (* syn_peri_port = 0 *) output jtag_inst1_TDO,

   //Clocks 
	input	wire	i_arstn,
    input	wire	i_mipi_rx_pclk,
    input wire  vid_clk_dvi2,
    input wire hdmi_tx_slow_clk,
    input wire [2:0] edge_keys_n, // KEY1/2/3 from attached key demo; KEY0 remains reset
    input wire CLK_5M,
    input  wire CLK_25M,
	output  wire    pll_inst1_RSTN,
	input	wire	i_pll_locked,
	input 	wire  	pll_locked,
	output  wire  	USER_PLL_RSTN,
    output 	wire 	DDR3_PLL_RSTN,
	input 	wire  	user_pll_locked,
    //CSI Interface
    input	 wire		io_cam_sda_IN,
    output wire   io_cam_sda_OUT,
    output wire		io_cam_sda_OE,

    output io_cam_scl_OUT,
    input io_cam_scl_IN,
    output io_cam_scl_OE,

    output	wire		o_cam_rst_p,
    
    input	wire		i_cam_ck_LP_P_IN,
    input	wire		i_cam_ck_LP_N_IN,
    output	wire		o_cam_ck_HS_TERM,
    output	wire		o_cam_ck_HS_ENA,
    input	wire		i_cam_ck_CLKOUT,
    
    input	wire	[7:0]			cam_d0_HS_IN,
    input	  wire		      cam_d0_LP_P_IN,
    input	  wire		      cam_d0_LP_N_IN,
    output	wire		      cam_d0_HS_TERM,
    output	wire		      cam_d0_HS_ENA,
    output	wire		      cam_d0_RST,
    output	wire		      cam_d0_FIFO_RD,
    input	  wire		      cam_d0_FIFO_EMPTY,
    
    input 	wire	[7:0]			cam_d1_HS_IN,
    input	  wire		        cam_d1_LP_P_IN,
    input	  wire		        cam_d1_LP_N_IN,
    output	wire		        cam_d1_HS_TERM,
    output	wire		        cam_d1_HS_ENA,
    output	wire		        cam_d1_RST,
    output	wire		        cam_d1_FIFO_RD,
    input	  wire		        cam_d1_FIFO_EMPTY,
    
    input 	wire	[7:0]			cam_d2_HS_IN,
    input	  wire		        cam_d2_LP_P_IN,
    input	  wire		        cam_d2_LP_N_IN,
    output	wire		        cam_d2_HS_TERM,
    output	wire		        cam_d2_HS_ENA,
    output	wire		        cam_d2_RST,
    output	wire		        cam_d2_FIFO_RD,
    input	  wire		        cam_d2_FIFO_EMPTY,  
   
    input 	wire	[7:0]			cam_d3_HS_IN,
    input	  wire		        cam_d3_LP_P_IN,
    input	  wire		        cam_d3_LP_N_IN,
    output	wire		        cam_d3_HS_TERM,
    output	wire		        cam_d3_HS_ENA,
    output	wire		        cam_d3_RST,
    output	wire		        cam_d3_FIFO_RD,
    input	  wire		        cam_d3_FIFO_EMPTY,

	
	input 					tx_cal_clk_90edge,
  	input 					rx_cal_clk,
  	input 					tx_cal_clk,
	input                              core_clk,     // CORE CLK @ 100MHz
	input                              sdram_clk,    // SDRAM CK @ 400MHz
	// PLL status flags  
	output [2:0]                       pll_shift,  
	output [4:0]                       pll_shift_sel,
	output                             pll_shift_ena,  
	// memory interface ports
	output                             ddr_ck_hi,
	output                             ddr_ck_lo,
	output                             ddr_reset_n,
	output [CKE_WIDTH-1:0]             ddr_cke,     
	output [ROW_WIDTH-1:0]             ddr_addr,
	output [BANK_WIDTH-1:0]            ddr_ba,
	output                             ddr_cas_n,
 
	output [CS_WIDTH*RANK_RATIO-1:0]   ddr_cs_n,
	output                             ddr_ras_n,
	output                             ddr_we_n,
	
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_hi,
	input  [DQS_WIDTH-1:0]             ddr_dqs_in_lo,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_hi,
	input  [DQ_WIDTH-1:0]              ddr_dq_in_lo,
	
	output [DQS_WIDTH-1:0]             ddr_dqs_oe,
	output [DQS_WIDTH-1:0]             ddr_dqs_oe_n,
	output [DQ_WIDTH-1:0]              ddr_dq_oe,  
	output [DQS_WIDTH-1:0]             ddr_dqs_out_hi,
	output [DQS_WIDTH-1:0]             ddr_dqs_out_lo,
	output [DQ_WIDTH-1:0]              ddr_dq_out_hi,
	output [DQ_WIDTH-1:0]              ddr_dq_out_lo,
	output [DM_WIDTH-1:0]              ddr_dm_hi,
	output [DM_WIDTH-1:0]              ddr_dm_lo,
	output [ODT_WIDTH-1:0]             ddr_odt,

       //LED
       output [7:0] led,

       // MIPI DSI
       input	wire	                     i_mipi_tx_pclk		,
       output	wire	                     mipi_dp_clk_LP_P_OUT		,
       output	wire	                     mipi_dp_clk_LP_N_OUT		,
       output	wire	[7:0] 	              mipi_dp_clk_HS_OUT		,
       output	wire	                     mipi_dp_clk_HS_OE		,
       output	wire	                     mipi_dp_data3_LP_P_OUT	,
       output	wire	                     mipi_dp_data2_LP_P_OUT	,
       output	wire	                     mipi_dp_data1_LP_P_OUT	,
       output	wire	                     mipi_dp_data0_LP_P_OUT	,
       output	wire	                     mipi_dp_data3_LP_N_OUT	,
       output	wire	                     mipi_dp_data2_LP_N_OUT	,
       output	wire	                     mipi_dp_data1_LP_N_OUT	,
       output	wire	                     mipi_dp_data0_LP_N_OUT	,
       output	wire	[7:0] 	              mipi_dp_data0_HS_OUT	       ,
       output	wire	[7:0] 	              mipi_dp_data1_HS_OUT	       ,
       output	wire	[7:0] 	              mipi_dp_data2_HS_OUT	       ,
       output	wire	[7:0] 	              mipi_dp_data3_HS_OUT	       ,
       output	wire	                     mipi_dp_data3_HS_OE		,
       output	wire	                     mipi_dp_data2_HS_OE		,
       output	wire	                     mipi_dp_data1_HS_OE		,
       output	wire	                     mipi_dp_data0_HS_OE		,

       output	wire	                     mipi_dp_clk_RST		,
       output	wire	                     mipi_dp_data0_RST		,
       output	wire	                     mipi_dp_data1_RST		,
       output	wire	                     mipi_dp_data2_RST		,
       output	wire	                     mipi_dp_data3_RST		,
       output	wire	                     mipi_dp_clk_LP_P_OE		,
       output	wire	                     mipi_dp_clk_LP_N_OE		,
       output	wire	                     mipi_dp_data3_LP_P_OE	,
       output	wire	                     mipi_dp_data3_LP_N_OE	,
       output	wire	                     mipi_dp_data2_LP_P_OE	,
       output	wire	                     mipi_dp_data2_LP_N_OE	,
       output	wire	                     mipi_dp_data1_LP_P_OE	,
       output	wire	                     mipi_dp_data1_LP_N_OE	,
       output	wire	                     mipi_dp_data0_LP_P_OE	,
       output	wire	                     mipi_dp_data0_LP_N_OE	,

       input  wire	                     mipi_dp_data0_LP_P_IN	,
       input  wire	                     mipi_dp_data0_LP_N_IN	,
       output	wire	                     LCD_RST_P			,
       output wire                        LCD_POWER			,

       // hdmi interface

    output tmds_tx_clk_TX_OE,
    output [9:0] tmds_tx_clk_TX_DATA,
    output tmds_tx_clk_TX_RST,
    output tmds_tx_data0_TX_OE,
    output [9:0] tmds_tx_data0_TX_DATA,
    output tmds_tx_data0_TX_RST,
    output tmds_tx_data1_TX_OE,
    output [9:0] tmds_tx_data1_TX_DATA,
    output tmds_tx_data1_TX_RST,
    output tmds_tx_data2_TX_OE,
    output [9:0] tmds_tx_data2_TX_DATA,
    output tmds_tx_data2_TX_RST


);

function integer log2;
	input	integer	val;
	integer	i;
	begin
		log2 = 0;
		for (i=0; 2**i<val; i=i+1)
			log2 = i+1;
	end
endfunction


//===============================================================================
//localparam
//===============================================================================
localparam WR_FIFO_DEPTH  = 1024;
localparam RD_FIFO_DEPTH  = 1024;

// localparam	MAX_HRES		= 12'd1920;
// localparam	MAX_VRES		= 12'd1080;
// localparam	HSP			= 8'd2;
// localparam	HBP			= 8'd88;
// localparam	HFP			= 8'd120;
// localparam	VSP			= 8'd2;
// localparam	VBP			= 8'd20;
// localparam	VFP			= 8'd20;

localparam HACT     = 1920;
localparam HFP      = 88;
localparam HSP      = 44;
localparam HBP      = 148;

localparam VACT     = 1080;
localparam VFP      = 4;
localparam VSP      = 5;
localparam VBP      = 36;
//===============================================================================
//signal
//===============================================================================
   
wire                              app_sr_active;
wire                              app_ref_ack;
wire                              app_zq_ack;
wire                              cal_done;
reg [26:0] dly_cnt = 'd0;
wire vid_rst_n;
wire gamma_sel;
wire [7:0] wrlvl_dq_check,rd_level_dqs_check;
wire [6:0] init_cur_state;
wire [1:0] video_format=2'd0;

// Slave Interface Write Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_awid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_awaddr;
wire [7:0]                        s_axi_awlen;
wire [2:0]                        s_axi_awsize;
wire [1:0]                        s_axi_awburst;
wire [0:0]                        s_axi_awlock;
wire [3:0]                        s_axi_awcache;
wire [2:0]                        s_axi_awprot;
wire                              s_axi_awvalid;
wire                              s_axi_awready;
// Slave Interface Write Data Ports
wire [AXI_DATA_WIDTH-1:0]         s_axi_wdata;
wire [(AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb;
wire                              s_axi_wlast;
wire                              s_axi_wvalid;
wire                              s_axi_wready;
// Slave Interface Write Response Ports
wire                              s_axi_bready;
wire [AXI_ID_WIDTH-1:0]           s_axi_bid;
wire [1:0]                        s_axi_bresp;
wire                              s_axi_bvalid;
// Slave Interface Read Address Ports
wire [AXI_ID_WIDTH-1:0]           s_axi_arid;
wire [AXI_ADDR_WIDTH-1:0]         s_axi_araddr;
wire [7:0]                        s_axi_arlen;
wire [2:0]                        s_axi_arsize;
wire [1:0]                        s_axi_arburst;
wire [0:0]                        s_axi_arlock;
wire [3:0]                        s_axi_arcache;
wire [2:0]                        s_axi_arprot;
wire                              s_axi_arvalid;
wire                              s_axi_arready;
// Slave Interface Read Data Ports
wire                              s_axi_rready;
wire [AXI_ID_WIDTH-1:0]           s_axi_rid;
wire [AXI_DATA_WIDTH-1:0]         s_axi_rdata;
wire [1:0]                        s_axi_rresp;
wire                              s_axi_rlast;
wire                              s_axi_rvalid;




////////////////////////////////////////////////////////////////
// System & Debugger
wire    w_arstn;
// wire	w_sysclk_mcu_arstn;
// wire	w_sysclk_mcu_arst;
wire	w_mipi_rx_pclk_arstn;
wire	w_mipi_rx_pclk_arst;

wire		       w_mipi_rx_vs;
wire		       w_mipi_rx_hs;
wire	       w_mipi_rx_de;
wire	[63:0]			w_mipi_rx_data	;

wire					io_systemReset;



//===================================================================================================
//reset module
//===================================================================================================

assign w_arstn  		       = i_arstn & i_pll_locked & pll_locked & user_pll_locked;
assign pll_inst1_RSTN  		= i_arstn;
assign USER_PLL_RSTN      		= i_arstn;
assign mipi_dsi_tx_pll_RSTN 	= i_arstn;
assign DDR3_PLL_RSTN 		= i_arstn;
reset_ctrl
#(
	.NUM_RST		(2),
	.CYCLE			(1),
	.IN_RST_ACTIVE	(4'b00),
	.OUT_RST_ACTIVE	(4'b10)
)
inst_reset_ctrl
(
	.i_arst		({2{w_arstn}}),//({{4{i_pll_locked}},                  {2{i_arstn}}}),
	.i_clk			({2{i_mipi_rx_pclk}}),
	.o_srst		({w_mipi_rx_pclk_arst, w_mipi_rx_pclk_arstn})
);



reg [25:0] cnt = 'd0;
always @( posedge core_clk)
begin 
       cnt <= cnt + 1'b1;
end
// LEDs are driven by the temporary camera diagnostic monitor below.

//========================================================================================================
//MIPI RX
//========================================================================================================
wire i_mipi_clk ;
assign i_mipi_clk = core_clk;

		assign	cam_d0_RST		= 1'b0;
		assign	cam_d1_RST		= 1'b0;
		assign  cam_d2_RST = 1'b0;
    assign  cam_d3_RST = 1'b0;
	
wire [31:0] mipi_debug_out;
		

		csi_rx_controller inst_efx_csi2_rx
		(
              .reset_n			(i_arstn),
              .clk				(i_mipi_clk),
              .reset_byte_HS_n	(i_arstn),
              .clk_byte_HS		  (i_cam_ck_CLKOUT),
              .reset_pixel_n		(w_mipi_rx_pclk_arstn),
              .clk_pixel			  (i_mipi_rx_pclk),
              
              .Rx_LP_CLK_P		  (i_cam_ck_LP_P_IN),
              .Rx_LP_CLK_N		  (i_cam_ck_LP_N_IN),
              .Rx_HS_enable_C		(o_cam_ck_HS_ENA),
              .LVDS_termen_C		(o_cam_ck_HS_TERM),
              
              .Rx_LP_D_P			({cam_d3_LP_P_IN, cam_d2_LP_P_IN, cam_d1_LP_P_IN, cam_d0_LP_P_IN}),//(r_mipi_rx_data_LP_P_IN_2P),
              .Rx_LP_D_N			({cam_d3_LP_N_IN, cam_d2_LP_N_IN, cam_d1_LP_N_IN, cam_d0_LP_N_IN}),//(r_mipi_rx_data_LP_N_IN_2P),
              .Rx_HS_D_0			(cam_d0_HS_IN),//(r_mipi_rx_data_HS_IN_2P[0*8+:8]),
              .Rx_HS_D_1			(cam_d1_HS_IN),//(r_mipi_rx_data_HS_IN_2P[1*8+:8]),
              .Rx_HS_D_2			(cam_d2_HS_IN),
              .Rx_HS_D_3			(cam_d3_HS_IN),
              .Rx_HS_D_4			(),
              .Rx_HS_D_5			(),
              .Rx_HS_D_6			(),
              .Rx_HS_D_7			(),
              .Rx_HS_enable_D		({cam_d3_HS_ENA    ,cam_d2_HS_ENA    ,cam_d1_HS_ENA    ,cam_d0_HS_ENA    }),//( w_cam_d_HS_ENA),
              .LVDS_termen_D		({cam_d3_HS_TERM   ,cam_d2_HS_TERM   ,cam_d1_HS_TERM   ,cam_d0_HS_TERM   }),
              .fifo_rd_enable		({cam_d3_FIFO_RD   ,cam_d2_FIFO_RD   ,cam_d1_FIFO_RD   ,cam_d0_FIFO_RD   }),
              .fifo_rd_empty		({cam_d3_FIFO_EMPTY,cam_d2_FIFO_EMPTY,cam_d1_FIFO_EMPTY,cam_d0_FIFO_EMPTY}),
              .DLY_enable_D		       (),
              .DLY_inc_D			(),
              .u_dly_enable_D		(),
              .u_dly_inc_D		       (),
              
              .axi_clk(core_clk),
              .axi_reset_n(i_arstn),
              .axi_awaddr			(6'b0),
              .axi_awvalid		       (1'b0),
              .axi_awready		       (),
              .axi_wdata			(32'b0),
              .axi_wvalid			(1'b0),
              .axi_wready			(),
              
              .axi_bvalid			(),
              .axi_bready			(1'b0),
              .axi_araddr			(6'b0),
              .axi_arvalid		       (1'b0),
              .axi_arready		       (),
              .axi_rdata			(),
              .axi_rvalid			(),
              .axi_rready			(1'b1),
              
              .hsync_vc0			(w_mipi_rx_hs),
              .hsync_vc1			(),
              .hsync_vc2			(),
              .hsync_vc3			(),
              .vsync_vc0			(w_mipi_rx_vs),
              .vsync_vc1			(),
              .vsync_vc2			(),
              .vsync_vc3			(),
              .vc				(),
              .word_count			(),
              .shortpkt_data_field        (),
              .datatype			(),
              .pixel_per_clk		(),
              .pixel_data			(w_mipi_rx_data),
              .pixel_data_valid	       (w_mipi_rx_de),
              .irq				(),
              .mipi_debug_in(32'b0),
              .mipi_debug_out(mipi_debug_out)
		);

//     wire		       w1_mipi_rx_vs;
// wire		       w1_mipi_rx_hs;
// wire	       w1_mipi_rx_de;
// wire	[39:0]			w1_mipi_rx_data	;
// sensor_clipper  sensor_clipper_inst (
//     .clk(i_mipi_rx_pclk),
//     .i_vs(w_mipi_rx_vs),
//     .i_hs(w_mipi_rx_hs),
//     .i_de(w_mipi_rx_de),
//     .i_dat(w_mipi_rx_data[39:0]),

//     .o_hs(w1_mipi_rx_hs),
//     .o_vs(w1_mipi_rx_vs),
//     .o_de(w1_mipi_rx_de),
//     .o_dat(w1_mipi_rx_data)
   
//   );


wire mdebug_pixel_fifo_full     = mipi_debug_out[0] ;
wire mdebug_pixel_fifo_empty    = mipi_debug_out[1] ;
wire mdebug_crc_error           = mipi_debug_out[2] ;
wire mdebug_ecc_1bit_error      = mipi_debug_out[3] ;
wire mdebug_ecc_2bit_error      = mipi_debug_out[4] ;
wire mdebug_undersize_pkt_error = mipi_debug_out[5] ;
wire mdebug_line_vc0_error      = mipi_debug_out[6] ;
wire mdebug_frame_vc0_error    = mipi_debug_out[10];   
wire mdebug_receive_error      = mipi_debug_out[14];


//========================================================================================================
//
//========================================================================================================
		

//*************** imx219 config********************/
// mipi_config_imx219_top u_config_imx219(
// 										.i_sys_clk(CLK_5M)    	,    /////48M 
// 										.sys_rstn(vid_rst_n )    ,
// 										.o_sen_rst_n(o_cam_rstn)  	,
										
										// .o_iic_sda_OE(io_cam_sda_OE) ,
										// .i_iic_sda(io_cam_sda_IN)   	,
										// .o_iic_sda(io_cam_sda_OUT)   	,
										// .o_iic_scl(io_cam_scl)    	
										// ); 	

wire scl_padoen_o;
wire sda_padoen_o;


reg [12:0] i2c_rst_cnt = '0;

always @( posedge CLK_5M or negedge w_arstn )
begin
    if( !w_arstn )
       i2c_rst_cnt <= 'd0;
    else 
       i2c_rst_cnt <= i2c_rst_cnt[12] ? i2c_rst_cnt : i2c_rst_cnt + 1'b1;
end
wire i2c_rst_n = i2c_rst_cnt[12];

i2c_master_ctrl_top u2_i2c_master_ctrl_top(
  /*i*/.clk			(CLK_5M		),
  /*i*/.rst_n			(i2c_rst_n		),
  /*i*/.scl_pad_i     (io_cam_scl_IN),//(1'b1),
  /*o*/.scl_pad_o     (io_cam_scl_OUT),
  /*o*/.scl_padoen_o  (scl_padoen_o),
  /*i*/.sda_pad_i     (io_cam_sda_IN),
  /*o*/.sda_pad_o     (io_cam_sda_OUT),
  /*o*/.sda_padoen_o  (sda_padoen_o)
  
  );
assign o_cam_rst_p = ~w_arstn;
assign io_cam_scl_OE = ~scl_padoen_o;
assign io_cam_sda_OE = ~sda_padoen_o;

//=====================================================================================
//frame buffer
//=====================================================================================
wire [7:0] 	ch0_r;
wire [7:0]    ch0_g;
wire [7:0]    ch0_b;
wire ch0_vs;
wire ch0_hs;
wire ch0_de;

wire  [16-1:0] m_axis_tdata;
wire           m_axis_tvalid;
wire           m_axis_tready;
wire           m_axis_tlast;
wire           m_axis_tuser;
wire  fifo_rd_period;
// IMX219

// Revised frame layer; retains the attached DDR3 controller and physical pins.
wire edge_cam_rst_n,edge_axi_rst_n;
wire edge_freeze;
wire [31:0] edge_completed,edge_selected,edge_rejected,edge_late,edge_rd_errors,edge_overflows;
wire edge_capture_overflow;
wire edge_video_underflow;
wire [31:0] edge_video_underflow_frames,edge_displayed_frames;
wire edge_store_arst_n=w_arstn && cal_done && dly_cnt[26];
img_reset_sync edge_cam_reset(.clk(i_mipi_rx_pclk),.arst_n(edge_store_arst_n),.rst_n(edge_cam_rst_n));
img_reset_sync edge_axi_reset(.clk(core_clk),.arst_n(edge_store_arst_n),.rst_n(edge_axi_rst_n));
assign s_axi_awid=0;assign s_axi_arid=0;
assign s_axi_awlock=0;assign s_axi_arlock=0;
assign s_axi_awcache=4'd3;assign s_axi_arcache=4'd3;
assign s_axi_awprot=3'd2;assign s_axi_arprot=3'd2;
assign s_axi_wstrb={AXI_DATA_WIDTH/8{1'b1}};
img_frame_store #(
    .I_BITS(32),.O_BITS(16),.AXI_BITS(AXI_DATA_WIDTH),.ADDR_BITS(AXI_ADDR_WIDTH),
    .WIDTH(HACT),.HEIGHT(VACT),.FIFO_DEPTH(2048),.MAX_BURST(128)
) edge_frame_store(
    .cam_clk(i_mipi_rx_pclk),.cam_rst_n(edge_cam_rst_n),
    .cam_vs(w_mipi_rx_vs),.cam_de(w_mipi_rx_de & w_mipi_rx_hs),
    .cam_data({w_mipi_rx_data[39:32],w_mipi_rx_data[29:22],w_mipi_rx_data[19:12],w_mipi_rx_data[9:2]}),
    .axi_clk(core_clk),.axi_rst_n(edge_axi_rst_n),.freeze(edge_freeze),
    .out_clk(vid_clk_dvi2),.out_rst_n(vid_rst_n),.frame_request(fifo_rd_period),
    .out_data(m_axis_tdata),.out_valid(m_axis_tvalid),.out_ready(m_axis_tready),
    .out_sof(m_axis_tuser),.out_eol(m_axis_tlast),
    .awaddr(s_axi_awaddr),.awlen(s_axi_awlen),.awsize(s_axi_awsize),.awburst(s_axi_awburst),
    .awvalid(s_axi_awvalid),.awready(s_axi_awready),
    .wdata(s_axi_wdata),.wvalid(s_axi_wvalid),.wlast(s_axi_wlast),.wready(s_axi_wready),
    .bvalid(s_axi_bvalid),.bresp(s_axi_bresp),.bready(s_axi_bready),
    .araddr(s_axi_araddr),.arlen(s_axi_arlen),.arsize(s_axi_arsize),.arburst(s_axi_arburst),
    .arvalid(s_axi_arvalid),.arready(s_axi_arready),
    .rdata(s_axi_rdata),.rvalid(s_axi_rvalid),.rlast(s_axi_rlast),.rresp(s_axi_rresp),.rready(s_axi_rready),
    .completed_frames(edge_completed),.selected_frames(edge_selected),.rejected_frames(edge_rejected),
    .late_requests(edge_late),.read_errors(edge_rd_errors),.capture_overflows(edge_overflows),
    .capture_overflow_sticky(edge_capture_overflow)
);

// V9: continuous 1080p60 timing. An empty display FIFO blanks the damaged
// frame and re-aligns at SOF; it cannot stop/restart the HDMI raster.
img_video_out #(
    .DATA_BITS(16),.PIXELS_PER_CLOCK(2),.WIDTH(HACT),.HEIGHT(VACT),
    .HFP(HFP),.HSP(HSP),.HBP(HBP),.VFP(VFP),.VSP(VSP),.VBP(VBP)
) edge_video_output (
    .clk(vid_clk_dvi2),.rst_n(vid_rst_n),.frame_request(fifo_rd_period),
    .in_data(m_axis_tdata),.in_valid(m_axis_tvalid),.in_ready(m_axis_tready),
    .in_sof(m_axis_tuser),.in_eol(m_axis_tlast),
    .out_data({ch0_b,ch0_g}),.out_hs(ch0_hs),.out_vs(ch0_vs),.out_de(ch0_de),
    .underflow_sticky(edge_video_underflow),.underflow_frames(edge_video_underflow_frames),
    .displayed_frames(edge_displayed_frames)
);


ddr3_top                 u_ddr3_top
(

.axi_clk                (core_clk            ),
.core_clk               (core_clk            ),
.sdram_clk              (sdram_clk           ),  
.rx_cal_clk             (rx_cal_clk          ),
.tx_cal_clk             (tx_cal_clk          ),
.tx_cal_clk_90edge      (tx_cal_clk_90edge   ),
.rstn                   (w_arstn             ),      
.pll_shift              (pll_shift           ),
.pll_shift_sel          (pll_shift_sel       ),
.pll_shift_ena          (pll_shift_ena       ),       
///////////////DDR BUS
.ddr_ck_hi              (ddr_ck_hi           ),
.ddr_ck_lo              (ddr_ck_lo           ),
.ddr_cke                (ddr_cke             ),    
.ddr_reset_n            (ddr_reset_n         ),
.ddr_cs_n               (ddr_cs_n            ),
.ddr_ras_n              (ddr_ras_n           ),
.ddr_cas_n              (ddr_cas_n           ),
.ddr_we_n               (ddr_we_n            ),     
.ddr_addr               (ddr_addr            ),
.ddr_ba                 (ddr_ba              ),

.ddr_dqs_oe             (ddr_dqs_oe          ),
.ddr_dqs_oe_n           (ddr_dqs_oe_n        ),
.ddr_dq_oe              (ddr_dq_oe           ),
.ddr_dqs_in_hi          (ddr_dqs_in_hi       ),
.ddr_dqs_in_lo          (ddr_dqs_in_lo       ),
.ddr_dq_in_hi           (ddr_dq_in_hi        ),
.ddr_dq_in_lo           (ddr_dq_in_lo        ),

.ddr_dqs_out_hi         (ddr_dqs_out_hi      ),
.ddr_dqs_out_lo         (ddr_dqs_out_lo      ),
.ddr_dq_out_hi          (ddr_dq_out_hi       ),
.ddr_dq_out_lo          (ddr_dq_out_lo       ),

.ddr_dm_hi              (ddr_dm_hi           ),
.ddr_dm_lo              (ddr_dm_lo           ),
.ddr_odt                (ddr_odt             ),

// Application interface ports
.app_sr_req                     (1'b0),
.app_ref_req                    (1'b0),
.app_zq_req                     (1'b0),
.app_sr_active                  (app_sr_active),
.app_ref_ack                    (app_ref_ack),
.app_zq_ack                     (app_zq_ack),

// Slave Interface Write Address Ports
.s_axi_awid                     (s_axi_awid        ),
.s_axi_awaddr                   (s_axi_awaddr      ),
.s_axi_awlen                    (s_axi_awlen       ),
.s_axi_awsize                   (s_axi_awsize      ),
.s_axi_awburst                  (s_axi_awburst     ),
.s_axi_awlock                   (s_axi_awlock      ),
.s_axi_awcache                  (s_axi_awcache     ),
.s_axi_awprot                   (s_axi_awprot      ),
.s_axi_awqos                    (4'h0              ),
.s_axi_awvalid                  (s_axi_awvalid     ),
.s_axi_awready                  (s_axi_awready     ),
// Slave Interface Write Data Ports
.s_axi_wdata                    (s_axi_wdata       ),
.s_axi_wstrb                    (s_axi_wstrb       ),
.s_axi_wlast                    (s_axi_wlast       ),
.s_axi_wvalid                   (s_axi_wvalid      ),
.s_axi_wready                   (s_axi_wready      ),
// Slave Interface Write Response Ports
.s_axi_bid                      (s_axi_bid         ),
.s_axi_bresp                    (s_axi_bresp       ),
.s_axi_bvalid                   (s_axi_bvalid      ),
.s_axi_bready                   (s_axi_bready      ),
// Slave Interface Read Address Ports
.s_axi_arid                     (s_axi_arid        ),
.s_axi_araddr                   (s_axi_araddr      ),
.s_axi_arlen                    (s_axi_arlen       ),
.s_axi_arsize                   (s_axi_arsize      ),
.s_axi_arburst                  (s_axi_arburst     ),
.s_axi_arlock                   (s_axi_arlock      ),
.s_axi_arcache                  (s_axi_arcache     ),
.s_axi_arprot                   (s_axi_arprot      ),
.s_axi_arqos                    (4'h0              ),
.s_axi_arvalid                  (s_axi_arvalid     ),
.s_axi_arready                  (s_axi_arready     ),
// Slave Interface Read Data Ports
.s_axi_rid                      (s_axi_rid         ),
.s_axi_rdata                    (s_axi_rdata       ),
.s_axi_rresp                    (s_axi_rresp       ),
.s_axi_rlast                    (s_axi_rlast       ),
.s_axi_rvalid                   (s_axi_rvalid      ),
.s_axi_rready                   (s_axi_rready      ),
//DEBUG       
.wrlvl_dq_check                 (wrlvl_dq_check    ) ,
.rd_level_dqs_check             (rd_level_dqs_check) ,
.init_cur_state                 (init_cur_state    ) ,
.idelay_ld                      (idelay_ld         ) ,
.mpr_rdlvl_dly                  (mpr_rdlvl_dly     ) ,
.cal_done                       (cal_done          ) 
);

//***************************************************************************
// debayer
//***************************************************************************


wire        rgb_vs;
wire        rgb_hs;
wire        rgb_de;
wire        rgb_valid;
wire [47:0] rgb_datax2;
wire [15:0] r_gain;
wire [15:0] g_gain;
wire [15:0] b_gain;
wire [1:0] edge_bayer_phase,edge_bayer_active;

// V10-C1: correct colors once, after interpolation. Keep the original VIO
// ports for diagnostic compatibility; this compile-time switch is rollback
// only. RAW unity must be 0x0100 in Q8.8, never 0x00ff.
localparam C1_LEGACY_RAW_VIO_GAIN=1'b0;

debayer_top_2to1 debayer_top
(
	.in_pclk		  (vid_clk_dvi2),//(i_mipi_rx_pclk ),
	.in_rstn		  (vid_rst_n	),
	
	.raw_vs_i		  (ch0_vs		      ),
	.raw_hs_i		  (ch0_hs		      ),
	.raw_de_i		  (ch0_de		      ),
	.raw_valid_i	(ch0_de	        ),
	.raw_datax4_i	({ch0_b,ch0_g}	),
	.bayer_phase(edge_bayer_phase),.bayer_active(edge_bayer_active),
	.r_gain       (C1_LEGACY_RAW_VIO_GAIN ? (|r_gain?r_gain:16'h0100) : 16'h0100),
  .g_gain       (C1_LEGACY_RAW_VIO_GAIN ? (|g_gain?g_gain:16'h0100) : 16'h0100),
  .b_gain       (C1_LEGACY_RAW_VIO_GAIN ? (|b_gain?b_gain:16'h0100) : 16'h0100),
	.rgb_vs_o		  (rgb_vs         ),
	.rgb_hs_o		  (rgb_hs         ),
	.rgb_de_o		  (rgb_de         ),
	.rgb_valid_o	(rgb_valid      ),
	.rgb_datax2_o (rgb_datax2     )//b,g,r,b,g,r
);
reg rgb_vs_r = 'd0;
always @( posedge hdmi_tx_slow_clk )
begin
  rgb_vs_r <= rgb_vs;
end
assign pos_vs = {rgb_vs_r,rgb_vs} == 2'b01;
reg vid_cnt = 'd0;
reg [7:0] hdmi_tx_rdata ;
reg [7:0] hdmi_tx_gdata ;
reg [7:0] hdmi_tx_bdata ;
reg hdmi_tx_vs;
reg hdmi_tx_hs;
reg hdmi_tx_de;
always @( posedge hdmi_tx_slow_clk )
begin
    if( pos_vs )
      vid_cnt <= 1'b1;
    else if( rgb_de )
      vid_cnt <= ~vid_cnt ;

    if( vid_cnt )
      {hdmi_tx_bdata,hdmi_tx_gdata,hdmi_tx_rdata} <= rgb_datax2[23:0];
    else 
      {hdmi_tx_bdata,hdmi_tx_gdata,hdmi_tx_rdata} <= rgb_datax2[47:24];

  hdmi_tx_vs <= rgb_vs;
  hdmi_tx_hs <= rgb_hs;
  hdmi_tx_de <= rgb_de;
end

// V3: diagnostic event toggles cross to HDMI in a 2-flop synchronizer in
// edge_video_health; event rates are <= one frame/clock domain, not pixel rate.
reg edge_cam_vs_q,edge_cam_frame_toggle;
always @(posedge i_mipi_rx_pclk or negedge edge_cam_rst_n) begin
    if (!edge_cam_rst_n) begin edge_cam_vs_q<=0;edge_cam_frame_toggle<=0;end
    else begin
        edge_cam_vs_q<=w_mipi_rx_vs;
        if (edge_cam_vs_q && !w_mipi_rx_vs) edge_cam_frame_toggle<=~edge_cam_frame_toggle;
    end
end
reg [31:0] edge_done_q,edge_selected_q,edge_reject_q,edge_late_q;
reg edge_done_toggle,edge_selected_toggle,edge_reject_toggle,edge_late_toggle;
always @(posedge core_clk or negedge edge_axi_rst_n) begin
    if(!edge_axi_rst_n) begin
        edge_done_q<=0;edge_selected_q<=0;edge_reject_q<=0;edge_late_q<=0;
        edge_done_toggle<=0;edge_selected_toggle<=0;edge_reject_toggle<=0;edge_late_toggle<=0;
    end else begin
        edge_done_q<=edge_completed;
        edge_selected_q<=edge_selected;
        edge_reject_q<=edge_rejected;
        edge_late_q<=edge_late;
        if(edge_done_q!=edge_completed) edge_done_toggle<=~edge_done_toggle;
        if(edge_selected_q!=edge_selected) edge_selected_toggle<=~edge_selected_toggle;
        if(edge_reject_q!=edge_rejected) edge_reject_toggle<=~edge_reject_toggle;
        if(edge_late_q!=edge_late) edge_late_toggle<=~edge_late_toggle;
    end
end
// Algorithm and UI run entirely in the one-pixel HDMI clock domain.
wire edge_pixel_rst_n;
img_reset_sync edge_pixel_reset(.clk(hdmi_tx_slow_clk),.arst_n(edge_store_arst_n),.rst_n(edge_pixel_rst_n));
reg edge_read_error_sticky;
always @(posedge core_clk) begin
    if(!edge_axi_rst_n)edge_read_error_sticky<=0;
    else if(edge_rd_errors!=0)edge_read_error_sticky<=1;
end
(* async_reg="true" *) reg [1:0] edge_underflow_sync,edge_read_error_sync;
always @(posedge hdmi_tx_slow_clk) begin
    if(!edge_pixel_rst_n) begin edge_underflow_sync<=0;edge_read_error_sync<=0;end
    else begin
        edge_underflow_sync<={edge_underflow_sync[0],edge_video_underflow};
        edge_read_error_sync<={edge_read_error_sync[0],edge_read_error_sticky};
    end
end
wire [23:0] edge_rgb;wire edge_de,edge_hs,edge_vs,edge_input_sof;
wire [10:0] edge_threshold,edge_pending_threshold,edge_magnitude;
wire [1:0] edge_preprocess;wire [2:0] edge_display;wire edge_binary;
wire [7:0] edge_key_press_count; wire [1:0] edge_last_key;
wire [9:0] edge_wb_r,edge_wb_g,edge_wb_b; wire [1:0] edge_wb_selected;
img_control edge_parameters(
    .clk(hdmi_tx_slow_clk),.rst_n(edge_pixel_rst_n),.keys_n(edge_keys_n),.frame_sof(edge_input_sof),
    .cfg_wr(1'b0),.cfg_addr(2'd0),.cfg_data(11'd0),
    .threshold(edge_threshold),.preprocess(edge_preprocess),.display(edge_display),
    .freeze(edge_freeze),.pending_threshold(edge_pending_threshold),
    .key_press_count(edge_key_press_count),.last_key(edge_last_key),
    .wb_r(edge_wb_r),.wb_g(edge_wb_g),.wb_b(edge_wb_b),.wb_selected(edge_wb_selected),
    .bayer_phase(edge_bayer_phase)
);
// Pixel-domain color balance is ONLY after the original Debayer and VIO block.
// All color and DE/HS/VS signals receive the SAME one-cycle delay.
wire [23:0] edge_balanced_rgb,edge_uncorrected_rgb;
wire [2:0] edge_color_clipped;
wire edge_balanced_de,edge_balanced_hs,edge_balanced_vs;
edge_color_balance edge_wb_processor(
    .clk(hdmi_tx_slow_clk),.rst_n(edge_pixel_rst_n),
    .in_rgb({hdmi_tx_rdata,hdmi_tx_gdata,hdmi_tx_bdata}),
    .in_de(hdmi_tx_de),.in_hs(hdmi_tx_hs),.in_vs(hdmi_tx_vs),
    .gain_r(edge_wb_r),.gain_g(edge_wb_g),.gain_b(edge_wb_b),
    .raw_rgb(edge_uncorrected_rgb),.bal_rgb(edge_balanced_rgb),
    .clipped_rgb(edge_color_clipped),
    .out_de(edge_balanced_de),.out_hs(edge_balanced_hs),.out_vs(edge_balanced_vs)
);
wire [7:0] edge_mean_raw_r,edge_mean_raw_g,edge_mean_raw_b;
wire [7:0] edge_mean_bal_r,edge_mean_bal_g,edge_mean_bal_b;
wire edge_rgb_valid; wire [8:0] edge_rgb_samples;
wire [8:0] edge_clip_r,edge_clip_g,edge_clip_b;
edge_rgb_statistics #(.WIDTH(HACT),.HEIGHT(VACT)) edge_wb_stats(
    .clk(hdmi_tx_slow_clk),.rst_n(edge_pixel_rst_n),
    .de(edge_balanced_de),.vs(edge_balanced_vs),
    .raw_rgb(edge_uncorrected_rgb),.balanced_rgb(edge_balanced_rgb),
    .clipped_rgb(edge_color_clipped),
    .mean_raw_r(edge_mean_raw_r),.mean_raw_g(edge_mean_raw_g),.mean_raw_b(edge_mean_raw_b),
    .mean_bal_r(edge_mean_bal_r),.mean_bal_g(edge_mean_bal_g),.mean_bal_b(edge_mean_bal_b),
    .sample_valid(edge_rgb_valid),.last_samples(edge_rgb_samples),
    .clipped_r(edge_clip_r),.clipped_g(edge_clip_g),.clipped_b(edge_clip_b)
);
img_pipeline #(.WIDTH(HACT),.HEIGHT(VACT),.HTOTAL(HACT+HFP+HSP+HBP),.NMS_ENABLE(E1_NMS_ENABLE),.NMS_STRICT_TIES(E1_NMS_STRICT_TIES)) edge_processing(
    .clk(hdmi_tx_slow_clk),.rst_n(edge_pixel_rst_n),
    .in_rgb(edge_balanced_rgb),
    .in_de(edge_balanced_de),.in_hs(edge_balanced_hs),.in_vs(edge_balanced_vs),
    .cfg_preprocess(edge_preprocess),.cfg_threshold(edge_threshold),.cfg_display(edge_display),
    .out_rgb(edge_rgb),.out_de(edge_de),.out_hs(edge_hs),.out_vs(edge_vs),
    .debug_magnitude(edge_magnitude),.debug_edge(edge_binary),.input_sof(edge_input_sof)
);
// V3: diagnostic HUD measures source-frame and completed-DDR-frame events
// per 60 output VS periods. It does not change resolution, sync, or latency.
wire [7:0] edge_cam_bcd,edge_done_bcd,edge_selected_bcd;
wire edge_reject_flag,edge_late_flag,edge_overflow_flag;

edge_video_health #(.WIDTH(HACT),.HEIGHT(VACT),.MEASURE_FRAMES(60)) video_health(
    .clk(hdmi_tx_slow_clk),.rst_n(edge_pixel_rst_n),
    .de(edge_de),.vs(edge_vs),.rgb(edge_rgb),.display_mode(edge_display),
    .cam_event_async(edge_cam_frame_toggle),
    .done_event_async(edge_done_toggle),
    .selected_event_async(edge_selected_toggle),
    .threshold_pending(edge_pending_threshold),
    .key_press_count(edge_key_press_count),.last_key(edge_last_key),
    .reject_event_async(edge_reject_toggle),
    .late_event_async(edge_late_toggle),
    .overflow_sticky_async(edge_capture_overflow),.freeze_active(edge_freeze),
    .cam_bcd(edge_cam_bcd),.done_bcd(edge_done_bcd),.selected_bcd(edge_selected_bcd),
    .reject_flag(edge_reject_flag),.late_flag(edge_late_flag),.overflow_flag(edge_overflow_flag),
    .out_rgb() // V8: retain diagnostic counters, suppress the legacy mini-overlay
);
// V7: retire the V5/V6 full-page text engine; the final-stage HUD is the
// only text generator. This also avoids duplicating expensive font logic.
wire [23:0] edge_diagnostics_rgb = edge_rgb; // leave all modes uncluttered
wire edge_diagnostics_de = edge_de;
wire edge_diagnostics_hs = edge_hs;
wire edge_diagnostics_vs = edge_vs;
// Gamma and its bypass both have one register of delay; identical RGB ordering.
wire [26:0] edge_gamma_bypass;
img_delay #(.BITS(27),.CYCLES(1)) edge_gamma_delay(
    .clk(hdmi_tx_slow_clk),.rst_n(edge_pixel_rst_n),
    .din({edge_diagnostics_vs,edge_diagnostics_hs,edge_diagnostics_de,edge_diagnostics_rgb}),.dout(edge_gamma_bypass)
);
reg edge_gamma_enable,edge_vs_q;
always @(posedge hdmi_tx_slow_clk) begin
    if(!edge_pixel_rst_n) begin edge_gamma_enable<=0;edge_vs_q<=0;end
    else begin
        edge_vs_q<=edge_diagnostics_vs;
        if(edge_diagnostics_vs && !edge_vs_q) edge_gamma_enable<=gamma_sel;
    end
end
//==============================================================================
// MIPI DSI
//==============================================================================
// signal 

reg		[25:0]	r_rst_cnt;

wire	[31:0]	w_axi_rdata;
wire			w_axi_awready;
wire			w_axi_wready;
wire			w_axi_arready;
wire			w_axi_rvalid;
wire			w_axi_bvalid;

wire	[6:0]	w_axi_awaddr;
wire			w_axi_awvalid;
wire	[31:0]	w_axi_wdata;
wire			w_axi_wvalid;
wire			w_axi_bready;
wire	[6:0]	w_axi_araddr;
wire			w_axi_arvalid;
wire			w_axi_rready;

wire			w_confdone;
assign w_confdone = 1'b1;

assign  LCD_POWER 			= i_arstn;
assign	LCD_RST_P	      = ~w_arstn;//~r_rst_cnt[23]; LCD复位先释放，然后再释放MIPI 的复位
assign	mipi_dp_clk_RST		= ~i_arstn;
assign	mipi_dp_data0_RST	= ~i_arstn;
assign	mipi_dp_data1_RST	= ~i_arstn;
assign	mipi_dp_data2_RST	= ~i_arstn;
assign	mipi_dp_data3_RST	= ~i_arstn;
////////////////////////////////////////////////////////////////
always@(posedge i_mipi_clk or  negedge w_arstn )
begin
  if ( !w_arstn ) begin
    r_rst_cnt	<= 'd0;
  end else 		
    r_rst_cnt	<= r_rst_cnt[25] ? r_rst_cnt :r_rst_cnt + 1'b1;
end

wire axi_rst_n = r_rst_cnt[25];



always @( posedge vid_clk_dvi2 or negedge w_arstn )
begin
  if( !w_arstn )
    dly_cnt <= 'd0;
  else if( w_confdone )
    dly_cnt <= dly_cnt[26] ? dly_cnt :(dly_cnt + 1'b1);
  else 
    dly_cnt <= 'd0;
end 


img_reset_sync edge_video_reset(.clk(vid_clk_dvi2),.arst_n(edge_store_arst_n),.rst_n(vid_rst_n));




wire hs;
wire vs;
wire de;
wire [7:0] rgb_r;
wire [7:0] rgb_g;
wire [7:0] rgb_b;
  
  // color_bar_rgb #(
  // .HS_POLORY 		(1'b1		),
  // .VS_POLORY 		(1'b1		),
  // .H_FRONT_PORCH 	(HFP[12:0]),///2
  // .H_SYNC 		(HSP[12:0]),//
  // .H_VALID 		(MAX_HRES	),//
  // .H_BACK_PORCH 	(HBP[12:0]),//
  // .V_FRONT_PORCH 	(VFP[12:0]),
  // .V_SYNC 		(VSP[12:0]),
  // .V_VALID 		(MAX_VRES	),
  // .V_BACK_PORCH 	(VBP[12:0]),
  // .TEST_MODE 		(2'd2)
  // )u_color_bar_rgb1(
  // /*i*/.clk	(vid_clk_dvi2),//(vid_clk),
  // /*i*/.rst_n	(vid_rst_n),
  // /*o*/.hs	(hs),
  // /*o*/.vs	(vs),
  // /*o*/.de	(de),
  // // /*O*/.h_cnt (h_cnt),
  // // /*O*/.v_cnt (v_cnt),
  // /*o*/.rgb_r	(rgb_r),    //像素数据、红色分量
  // /*o*/.rgb_g	(rgb_g),    //像素数据、绿色分量
  // /*o*/.rgb_b (rgb_b)    //像素数据、蓝色分量
  
  // );

//=================================================================================
//hdmi tx ctrl 
//=================================================================================
wire                            video_hs;
wire                            video_vs;
wire                            video_de;
wire[7:0]                       video_r;
wire[7:0]                       video_g;
wire[7:0]                       video_b;

assign tmds_tx_data0_TX_OE = 1'b1;
assign tmds_tx_data1_TX_OE = 1'b1;
assign tmds_tx_data2_TX_OE = 1'b1;
assign tmds_tx_clk_TX_OE   = 1'b1;

assign tmds_tx_data0_TX_RST = 1'b0;
assign tmds_tx_data1_TX_RST = 1'b0;
assign tmds_tx_data2_TX_RST = 1'b0;
assign tmds_tx_clk_TX_RST   = 1'b0;

// 	  color_bar color_bar_m0(
// 	.clk(hdmi_tx_slow_clk),
// 	.rst(~vid_rst_n),
// 	.hs(video_hs),
// 	.vs(video_vs),
// 	.de(video_de),
// 	.rgb_r(video_r),
// 	.rgb_g(video_g),
// 	.rgb_b(video_b)
// );

wire [9:0] tmds_data0;
wire [9:0] tmds_data1;
wire [9:0] tmds_data2;
wire [9:0] tmds_clk ;
wire [7:0] gamma_rdata ;
wire [7:0] gamma_gdata ;
wire [7:0] gamma_bdata ;
wire gamma_valid;
wire gamma_hs;
wire gamma_vs;


wire [7:0] con_rdata ;
wire [7:0] con_gdata ;
wire [7:0] con_bdata ;
wire con_de;
wire con_hs;
wire con_vs;
wire con_sel;

wire [7:0] BRIGHT_SIG    ;
wire CONTRAST_SIG_G;
wire CONTRAST_SIG_R;
wire [7:0] CONTRAST_G    ;
wire CONTRAST_SIG_B;
wire [7:0] BRIGHT        ;
wire [7:0] CONTRAST_R    ;


wire CONTRAST_B    ;


gamma_correction
#(
	.DATA_WIDTH		(8),
	.GAMMA_CURVE	("./rtl/gamma_conrrection/2P2.mem")
)
inst_gamma_correction
(
	.i_pclk		(hdmi_tx_slow_clk),
	.i_rstn		(edge_pixel_rst_n),
	
	.i_red		(edge_diagnostics_rgb[23:16]),//(con_rdata  ),//
	.i_green	(edge_diagnostics_rgb[15:8]),//(con_gdata  ),//
	.i_blue		(edge_diagnostics_rgb[7:0]),//(con_bdata  ),//
  .i_valid	(edge_diagnostics_de      ),//(con_de     ),//
  .i_hs     (edge_diagnostics_hs      ),//(con_hs     ),//
  .i_vs     (edge_diagnostics_vs      ),//(con_vs     ),//
	.o_blue		(gamma_bdata		),
  .o_green	(gamma_gdata	  ),
	.o_red		(gamma_rdata		),
	.o_valid	(gamma_valid	  ),
  .o_hs     (gamma_hs       ),
  .o_vs     (gamma_vs       )
);

// V8: final-encoder HUD only on mode 6 (full RGB white-balance calibration).
// Mode 0 is clean RGB; mode 3 is clean RGB/edge split; all other modes clean.
wire [23:0] edge_preencoder_rgb = edge_gamma_enable ?
    {gamma_rdata,gamma_gdata,gamma_bdata} : edge_gamma_bypass[23:0];
wire edge_preencoder_de = edge_gamma_enable ? gamma_valid : edge_gamma_bypass[24];
wire edge_preencoder_hs = edge_gamma_enable ? gamma_hs : edge_gamma_bypass[25];
wire edge_preencoder_vs = edge_gamma_enable ? gamma_vs : edge_gamma_bypass[26];
wire [23:0] edge_final_hdmi_rgb;
wire edge_final_hdmi_de,edge_final_hdmi_hs,edge_final_hdmi_vs;
edge_final_hud #(.WIDTH(HACT),.HEIGHT(VACT),.NMS_ENABLE(E1_NMS_ENABLE)) edge_final_hdmi_hud(
    .clk(hdmi_tx_slow_clk),.rst_n(edge_pixel_rst_n),
    .in_rgb(edge_preencoder_rgb),.in_de(edge_preencoder_de),
    .in_hs(edge_preencoder_hs),.in_vs(edge_preencoder_vs),
    .mean_raw_r(edge_mean_raw_r),.mean_raw_g(edge_mean_raw_g),.mean_raw_b(edge_mean_raw_b),
    .mean_bal_r(edge_mean_bal_r),.mean_bal_g(edge_mean_bal_g),.mean_bal_b(edge_mean_bal_b),
    .last_samples(edge_rgb_samples),.sample_valid(edge_rgb_valid),
    .clipped_r(edge_clip_r),.clipped_g(edge_clip_g),.clipped_b(edge_clip_b),
    .wb_r(edge_wb_r),.wb_g(edge_wb_g),.wb_b(edge_wb_b),.wb_selected(edge_wb_selected),
    .bayer_phase(edge_bayer_active),
    .threshold(edge_pending_threshold),.display_mode(edge_display),
    .key_press_count(edge_key_press_count),
    .cam_bcd(edge_cam_bcd),.done_bcd(edge_done_bcd),.selected_bcd(edge_selected_bcd),
    .reject_flag(edge_reject_flag),.late_flag(edge_late_flag),
    .overflow_flag(edge_overflow_flag),.freeze_active(edge_freeze),
    .underflow_flag(edge_underflow_sync[1]),.read_error_flag(edge_read_error_sync[1]),
    .out_rgb(edge_final_hdmi_rgb),.out_de(edge_final_hdmi_de),
    .out_hs(edge_final_hdmi_hs),.out_vs(edge_final_hdmi_vs)
);

dvi_encoder dvi_encoder_m0
(
	.pixelclk      		(hdmi_tx_slow_clk          ),// system clock
	.rst_p         		(~edge_pixel_rst_n),// reset
	.i_bdata         (edge_final_hdmi_rgb[7:0]),
	.i_gdata         (edge_final_hdmi_rgb[15:8]),
	.i_rdata         (edge_final_hdmi_rgb[23:16]),
	.i_de            (edge_final_hdmi_de),
	.i_hs            (edge_final_hdmi_hs),
	.i_vs            (edge_final_hdmi_vs),
	
  .video_format     (video_format), //// 00 = RGB, 01 = YCbCr 4:2:2, 10 = YCbCr 4:4:4
  .video_VIC        (7'd0),
	.audio_L (24'd0),
  .audio_R (24'd0),
  .audio_valid (1'd0),
  .audio_N (20'd6144),     //(20'h01880),//     
  .audio_CTS (20'd148500),      //(20'h28488),//      
  .audio_sample_frequency (4'd0),    //(3'b000),// 
  .audio_word_length (4'd0),//(4'b1011),//

	.tmds_data0    		(tmds_data0),
  .tmds_data1    		(tmds_data1),
  .tmds_data2    		(tmds_data2),
  .tmds_clk      	  (tmds_clk  )
);
assign tmds_tx_clk_TX_DATA   = ~tmds_clk;
assign tmds_tx_data0_TX_DATA = ~tmds_data0;
assign tmds_tx_data1_TX_DATA = ~tmds_data1;
assign tmds_tx_data2_TX_DATA = ~tmds_data2;

// Temporary camera test, upstream of DDR and image processing.
// LED status: 0 core clock heartbeat, 1 pixel clock heartbeat, 2 valid pixels,
// 3 VS seen, 4 expected-size frame, 5 DDR frame published, 6 RX error,
// 7 pixel values changed. Status bits 2..7 latch until KEY0 is pressed.
camera_diag_monitor #(.EXPECTED_WORDS(HACT*VACT/4)) camera_diag_inst(
 .rst_n(i_arstn),.ref_clk(core_clk),.cam_clk(i_mipi_rx_pclk),.axi_clk(core_clk),
 .cam_ready(w_mipi_rx_pclk_arstn),.cam_vs(w_mipi_rx_vs),.cam_hs(w_mipi_rx_hs),
 .cam_valid(w_mipi_rx_de),.cam_data(w_mipi_rx_data[39:0]),
 .rx_init_done(mipi_debug_out[15]),.rx_error(|(mipi_debug_out & 32'h0000447d)),
 .completed_frames(edge_completed),.status(led)
);

debug_edb_top debug_edb_top_inst (
    .bscan_CAPTURE      ( jtag_inst1_CAPTURE  ),
    .bscan_DRCK         ( jtag_inst1_DRCK     ),
    .bscan_RESET        ( jtag_inst1_RESET    ),
    .bscan_RUNTEST      ( jtag_inst1_RUNTEST  ),
    .bscan_SEL          ( jtag_inst1_SEL      ),
    .bscan_SHIFT        ( jtag_inst1_SHIFT    ),
    .bscan_TCK          ( jtag_inst1_TCK      ),
    .bscan_TDI          ( jtag_inst1_TDI      ),
    .bscan_TMS          ( jtag_inst1_TMS      ),
    .bscan_UPDATE       ( jtag_inst1_UPDATE   ),
    .bscan_TDO          ( jtag_inst1_TDO      ),
    .vio0_clk           ( vid_clk_dvi2        ),
    .vio0_r_gain        ( r_gain              ),
    .vio0_g_gain        ( g_gain              ),
    .vio0_b_gain        ( b_gain              ),

    .vio0_gamma_sel     (gamma_sel),
    .la0_clk(i_mipi_rx_pclk),
    .la0_ch0_g(w_mipi_rx_data[9:2]),
    .la0_ch0_b(w_mipi_rx_data[19:12]),
    .la0_ch0_de(w_mipi_rx_de),
    .la0_cal_done(w_mipi_rx_vs)
);

endmodule

// Temporary camera diagnostic monitor. Flags latch until KEY0 reset.
// Complete-frame evidence counts valid four-pixel words between falling VS
// boundaries; it does not replace CRC checks or verify image geometry per line.
module camera_diag_monitor #(
    parameter integer EXPECTED_WORDS=518400,
    parameter integer HEARTBEAT_BIT=24
)(
    input wire rst_n, ref_clk, cam_clk, axi_clk,
    input wire cam_ready, cam_vs, cam_hs, cam_valid,
    input wire [39:0] cam_data,
    input wire rx_init_done, rx_error,
    input wire [31:0] completed_frames,
    output wire [7:0] status
);
    reg [HEARTBEAT_BIT:0] ref_counter, cam_counter;
    reg vs_q, armed, pixel_seen, vs_seen, frame_seen, changing_seen;
    reg previous_valid;
    reg [39:0] previous_data;
    reg [31:0] frame_words;
    reg ddr_seen, error_seen;
    wire [7:0] asynchronous_status = {
        changing_seen,error_seen,ddr_seen,frame_seen,vs_seen,pixel_seen,
        cam_counter[HEARTBEAT_BIT],1'b0
    };
    (* async_reg="true" *) reg [7:0] status_sync1,status_sync2;
    always @(posedge ref_clk or negedge rst_n) begin
        if(!rst_n) begin ref_counter<=0;status_sync1<=0;status_sync2<=0;end
        else begin
            ref_counter<=ref_counter+1'b1;
            status_sync1<=asynchronous_status;status_sync2<=status_sync1;
        end
    end
    assign status={status_sync2[7:1],ref_counter[HEARTBEAT_BIT]};
    always @(posedge axi_clk or negedge rst_n) begin
        if(!rst_n) begin ddr_seen<=0;error_seen<=0;end
        else begin
            if(completed_frames!=0) ddr_seen<=1;
            if(rx_init_done && rx_error) error_seen<=1;
        end
    end
    always @(posedge cam_clk or negedge rst_n) begin
        if(!rst_n) begin
            cam_counter<=0;vs_q<=0;armed<=0;frame_words<=0;
            pixel_seen<=0;vs_seen<=0;frame_seen<=0;changing_seen<=0;
            previous_valid<=0;previous_data<=0;
        end else begin
            cam_counter<=cam_counter+1'b1;
            vs_q<=cam_vs;
            if(!cam_ready) begin armed<=0;frame_words<=0;previous_valid<=0;end
            else begin
                if(cam_vs!=vs_q) vs_seen<=1;
                if(cam_valid) begin
                    pixel_seen<=1;
                    if(previous_valid && cam_data!=previous_data) changing_seen<=1;
                    previous_valid<=1;previous_data<=cam_data;
                end
                if(vs_q && !cam_vs) begin
                    if(armed && frame_words==EXPECTED_WORDS) frame_seen<=1;
                    armed<=1;frame_words<=0;
                end else if(armed && cam_valid && cam_hs && frame_words!=32'hffffffff)
                    frame_words<=frame_words+1'b1;
            end
        end
    end
endmodule

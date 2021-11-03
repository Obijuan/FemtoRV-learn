// femtorv32, a minimalistic RISC-V RV32I core
//    (minus SYSTEM and FENCE that are not implemented)
//
//       Bruno Levy, May-June 2020
//
// This file: the "System on Chip" that goes with femtorv32.

/*************************************************************************************/


`default_nettype none // Makes it easier to detect typos !

`define NRV_FREQ 50                 // Validated at 50 MHz on the IceStick. Can overclock to 70 MHz.
`define NRV_RESET_ADDR 32'h00820000 // Jump execution to SPI Flash (800000h, +128k(20000h) for FPGA bitstream)
`define NRV_COUNTER_WIDTH 24        // Number of bits in cycles counter
`define NRV_ADDR_WIDTH 24

/************************* RAM (in bytes, needs to be a multiple of 4)***********************************************/
`define NRV_RAM 6144 // default for ICESTICK (cannot do more !)
`define NRV_IS_IO_ADDR(addr) |addr[23:22] 


module femtosoc(
   output D1,D2,D3,D4,D5,	      
   input  RXD,
   output TXD,	      
   inout spi_mosi, inout spi_miso, output spi_cs_n,
   output spi_clk, 
   input  RESET, 		
   input pclk
);

/********************* Technicalities **************************************/	

  wire  clk;
   
  femtoPLL #(
    .freq(`NRV_FREQ)	     
  ) pll(
    .pclk(pclk), 
    .clk(clk)
  );

  // A little delay for sending the reset signal after startup.
  // Explanation here: (ice40 BRAM reads incorrect values during
  // first cycles).
  // http://svn.clifford.at/handicraft/2017/ice40bramdelay/README
  // On the ICE40-UP5K, 4096 cycles do not suffice (-> 65536 cycles)

  reg [11:0] reset_cnt = 0;   
  wire       reset = &reset_cnt;


   always @(posedge clk,posedge RESET) begin
      if(RESET) begin
	 reset_cnt <= 0;
      end else begin
	 reset_cnt <= reset_cnt + !reset;
      end
   end
   
/***************************************************************************************************
/*
 * Memory and memory interface
 * memory map:
 *   address[21:2] RAM word address (4 Mb max).
 *   address[23:22]   00: RAM
 *                    01: IO page (1-hot)  (starts at 0x400000)
 *                    10: SPI Flash page   (starts at 0x800000)
 */ 

   // The memory bus.
   wire [31:0] mem_address; // 24 bits are used internally. The two LSBs are ignored (using word addresses)
   wire  [3:0] mem_wmask;   // mem write mask and strobe /write Legal values are 000,0001,0010,0100,1000,0011,1100,1111
   wire [31:0] mem_rdata;   // processor <- (mem and peripherals) 
   wire [31:0] mem_wdata;   // processor -> (mem and peripherals)
   wire        mem_rstrb;   // mem read strobe. Goes high to initiate memory write.
   wire        mem_rbusy;   // processor <- (mem and peripherals). Stays high until a read transfer is finished.
   wire        mem_wbusy;   // processor <- (mem and peripherals). Stays high until a write transfer is finished.

   wire        mem_wstrb = |mem_wmask; // mem write strobe, goes high to initiate memory write (deduced from wmask)

   // IO bus.
   wire mem_address_is_ram       = (mem_address[23:22] == 2'b00);   
   wire mem_address_is_io        = (mem_address[23:22] == 2'b01);
   wire mem_address_is_spi_flash = (mem_address[23:22] == 2'b10);
   wire mapped_spi_flash_rbusy;
   wire [31:0] mapped_spi_flash_rdata;
   
   MappedSPIFlash mapped_spi_flash(
      .clk(clk),
      .rstrb(mem_rstrb && mem_address_is_spi_flash),
      .word_address(mem_address[21:2]),
      .rdata(mapped_spi_flash_rdata),
      .rbusy(mapped_spi_flash_rbusy),
      .CLK(spi_clk),
      .CS_N(spi_cs_n),			   
      .IO({spi_miso,spi_mosi})			   
   );
      
   reg  [31:0] io_rdata; 
   wire [31:0] io_wdata = mem_wdata;
   wire        io_rstrb = mem_rstrb && mem_address_is_io;
   wire        io_wstrb = mem_wstrb && mem_address_is_io;
   wire [19:0] io_word_address = mem_address[21:2]; // word offset in io page
   wire	       io_rbusy; 
   wire        io_wbusy;
   
   assign      mem_rbusy = io_rbusy | mapped_spi_flash_rbusy;
   
   assign      mem_wbusy = io_wbusy; 
   parameter mem_address_is_vram = 1'b0;

   wire [19:0] ram_word_address = mem_address[21:2];


   
   reg [31:0] RAM[0:(`NRV_RAM/4)-1];
   reg [31:0] ram_rdata;

   // The power of YOSYS: it infers BRAM primitives automatically ! (and recognizes
   // masked writes, amazing ...)
   /* verilator lint_off WIDTH */
   always @(posedge clk) begin
      if(mem_address_is_ram && !mem_address_is_vram) begin
	 if(mem_wmask[0]) RAM[ram_word_address][ 7:0 ] <= mem_wdata[ 7:0 ];
	 if(mem_wmask[1]) RAM[ram_word_address][15:8 ] <= mem_wdata[15:8 ];
	 if(mem_wmask[2]) RAM[ram_word_address][23:16] <= mem_wdata[23:16];
	 if(mem_wmask[3]) RAM[ram_word_address][31:24] <= mem_wdata[31:24];	 
      end 
      ram_rdata <= RAM[ram_word_address];
   end
   /* verilator lint_on WIDTH */
   
   assign mem_rdata = mem_address_is_io  ? io_rdata  : 
		      mem_address_is_ram ? ram_rdata : 
		      mapped_spi_flash_rdata;   
   
/***************************************************************************************************
/*
 * Memory-mapped IO
 * Mapped IO uses "one-hot" addressing, to make decoder
 * simpler (saves a lot of LUTs), as in J1/swapforth,
 * thanks to Matthias Koch(Mecrisp author) for the idea !
 * The included files contains the symbolic constants that
 * determine which device uses which bit.
 */  

// We got a total of 20 bits for 1-hot addressing of IO registers.

localparam IO_LEDS_bit                  = 0;  // RW four leds
localparam IO_UART_DAT_bit              = 1;  // RW write: data to send (8 bits) read: received data (8 bits)
localparam IO_UART_CNTL_bit             = 2;  // R  status. bit 8: valid read data. bit 9: busy sending
localparam IO_SSD1351_CNTL_bit          = 3;  // W  Oled display control
localparam IO_SSD1351_CMD_bit           = 4;  // W  Oled display commands (8 bits)
localparam IO_SSD1351_DAT_bit           = 5;  // W  Oled display data (8 bits)
localparam IO_SSD1351_DAT16_bit         = 6;  // W  Oled display data (16 bits)
localparam IO_MAX7219_DAT_bit           = 7;  // W  led matrix data (16 bits)
localparam IO_SDCARD_bit                = 8;  // RW write: bit 0: mosi  bit 1: clk   bit 2: csn read: miso
localparam IO_BUTTONS_bit               = 9;  // R  buttons state
localparam IO_FGA_CNTL_bit              = 10; // RW write: send command  read: get VSync/HSync/MemBusy/X/Y state
localparam IO_FGA_DAT_bit               = 11; // W  write: write pixel data

// The three constant hardware config registers, using the three last bits of IO address space
localparam IO_HW_CONFIG_RAM_bit     = 17;  // R  total quantity of RAM, in bytes
localparam IO_HW_CONFIG_DEVICES_bit = 18;  // R  configured devices
localparam IO_HW_CONFIG_CPUINFO_bit = 19;  // R  CPU information CPL(6) FREQ(10) RESERVED(16)

// These devices do not have hardware registers. Just a bit set in IO_HW_CONFIG_DEVICES
localparam IO_MAPPED_SPI_FLASH_bit  = 20;  // no register (just there to indicate presence)

   
/*********************** Four LEDs ************************/
   wire [31:0] leds_rdata;
   LEDDriver leds(	  
      .clk(clk),
      .rstrb(io_rstrb),		  
      .wstrb(io_wstrb),			
      .sel(io_word_address[IO_LEDS_bit]),
      .wdata(io_wdata),		  
      .rdata(leds_rdata),
      .LED({D4,D3,D2,D1})
   );

/********************** UART ****************************************/

 // Internal wires to connect IO buffers to UART
 wire RXD_internal;
 wire TXD_internal;

 
 // For other boards, we directly connect RXD and TXD to the UART (but we may need
 // to latch).
 
   assign RXD_internal = RXD;
   assign TXD = TXD_internal;

   wire        uart_brk;
   wire [31:0] uart_rdata;
   UART uart(
      .clk(clk),
      .rstrb(io_rstrb),	     	     
      .wstrb(io_wstrb),
      .sel_dat(io_word_address[IO_UART_DAT_bit]),
      .sel_cntl(io_word_address[IO_UART_CNTL_bit]),	     
      .wdata(io_wdata),
      .rdata(uart_rdata),
      .RXD(RXD_internal),
      .TXD(TXD_internal),
      .brk(uart_brk)
   );
   
/************** io_rdata, io_rbusy and io_wbusy signals *************/

/*
 * io_rdata is latched. Not mandatory, but probably allow higher freq, to be tested.
 */
always @(posedge clk) begin
   io_rdata <= 0       
	    | leds_rdata  | uart_rdata    ;
end

   // For now, we got no device that has
   // blocking reads (SPI flash blocks on
   // write address and waits for read data).
   assign io_rbusy = 0 ; 

   assign io_wbusy = 0; 

/****************************************************************/
/* And last but not least, the processor                        */
   
  reg error=1'b0;

   
  FemtoRV32 #(
     .ADDR_WIDTH(`NRV_ADDR_WIDTH),
     .RESET_ADDR(`NRV_RESET_ADDR)	      
  ) processor(
    .clk(clk),			
    .mem_addr(mem_address),
    .mem_wdata(mem_wdata),
    .mem_wmask(mem_wmask),
    .mem_rdata(mem_rdata),
    .mem_rstrb(mem_rstrb),
    .mem_rbusy(mem_rbusy),
    .mem_wbusy(mem_wbusy),    
    .reset(reset && !uart_brk)
  );

   assign D5 = error;
   
endmodule

// femtorv32, a minimalistic RISC-V RV32I core
//    (minus SYSTEM and FENCE that are not implemented)
//
//       Bruno Levy, May-June 2020
//
// This file: the "System on Chip" that goes with femtorv32.

/*************************************************************************************/


`default_nettype none // Makes it easier to detect typos !

`define NRV_IO_LEDS          // Mapped IO, LEDs D1,D2,D3,D4 (D5 is used to display errors)
`define NRV_IO_IRDA          // In IO_LEDS, support for the IRDA on the IceStick (WIP)
`define NRV_IO_UART          // Mapped IO, virtual UART (USB)
`define NRV_MAPPED_SPI_FLASH // SPI flash mapped in address space. Use with MINIRV32 to run code from SPI flash.


`define NRV_FEMTORV32_QUARK
`define NRV_FREQ 50                 // Validated at 50 MHz on the IceStick. Can overclock to 70 MHz.
`define NRV_RESET_ADDR 32'h00820000 // Jump execution to SPI Flash (800000h, +128k(20000h) for FPGA bitstream)
`define NRV_COUNTER_WIDTH 24        // Number of bits in cycles counter
`define NRV_TWOLEVEL_SHIFTER        // Faster shifts

/************************* RAM (in bytes, needs to be a multiple of 4)***********************************************/

`define NRV_RAM 6144 // default for ICESTICK (cannot do more !)

/************************* Advanced devices configuration ***********************************************************/

`define NRV_RUN_FROM_SPI_FLASH // Do not 'readmemh()' firmware from '.hex' file
`define NRV_IO_HARDWARE_CONFIG // Comment-out to disable hardware config registers mapped in IO-Space
                               // (note: firmware libfemtorv32 depends on it)

/********************************************************************************************************************/

`define NRV_CONFIGURED

`define NRV_SPI_FLASH
`define ICE40
`define NRV_IS_IO_ADDR(addr) |addr[23:22] 

// Firmware generation flags for this processor
`define NRV_ARCH     "rv32i"
`define NRV_ABI      "ilp32"
`define NRV_OPTIMIZE "-Os"

`define SPI_FLASH_FAST_READ_DUAL_IO
`define SPI_FLASH_CONFIGURED

`ifndef SPI_FLASH_DUMMY_CLOCKS
 `define SPI_FLASH_DUMMY_CLOCKS 8
`endif

`define SPI_FLASH_READ


module LEDDriver(
`ifdef NRV_IO_IRDA
    output wire irda_TXD,
    input  wire irda_RXD,
    output wire irda_SD,		
`endif		  
    input wire 	       clk, // system clock
    input wire 	       rstrb, // read strobe		
    input wire 	       wstrb, // write strobe
    input wire 	       sel, // select (read/write ignored if low)
    input wire [31:0]  wdata, // data to be written
    output wire [31:0] rdata, // read data
    output wire [3:0]  LED    // LED pins
);

// The IceStick has an infrared reveiver/transmitter pair
// See EXAMPLES/test_ir_sensor.c and EXAMPLES/test_ir_remote.c
`ifdef NRV_IO_IRDA
   reg [5:0] led_state;
   assign LED = led_state[3:0];
   assign rdata = (sel ? {25'b0, irda_RXD, led_state} : 32'b0);
   assign irda_SD  = led_state[5];
   assign irda_TXD = led_state[4];
`else   
   reg [3:0] led_state;
   assign LED = led_state;
   
   initial begin
      led_state = 4'b0000;
   end
   
   assign rdata = (sel ? {28'b0, led_state} : 32'b0);
`endif
   
   always @(posedge clk) begin
      if(sel && wstrb) begin
`ifdef NRV_IO_IRDA
	 led_state <= wdata[5:0];
`else
	 led_state <= wdata[3:0];	 
`endif	 
`ifdef BENCH
         $display("****************** LEDs = %b", wdata[3:0]);
`endif	 
      end
   end
endmodule


module Buttons(
    input wire 	       sel,   // select (read/write ignored if low)
    output wire [31:0] rdata, // read data

    input wire[5:0]   BUTTONS // the six pins wired to the buttons
);

   assign rdata = (sel ? {26'b0, BUTTONS} : 32'b0);

endmodule



module HardwareConfig(
    input wire 	       clk, 
    input wire 	       sel_memory,  // available RAM
    input wire 	       sel_devices, // configured devices 
    input wire         sel_cpuinfo, // CPU information 	      
    output wire [31:0] rdata        // read data
);

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




`ifdef NRV_COUNTER_WIDTH
   localparam counter_width = `NRV_COUNTER_WIDTH;
`else
   localparam counter_width = 32;
`endif   

   
// configured devices
localparam NRV_DEVICES = 0
`ifdef NRV_IO_LEDS
   | (1 << IO_LEDS_bit)			 
`endif			    
`ifdef NRV_IO_UART
   | (1 << IO_UART_DAT_bit) | (1 << IO_UART_CNTL_bit)
`endif			    
`ifdef NRV_IO_SSD1351_1331
   | (1 << IO_SSD1351_CNTL_bit) | (1 << IO_SSD1351_CMD_bit) | (1 << IO_SSD1351_DAT_bit)  
`endif			    
`ifdef NRV_IO_MAX7219     
   | (1 << IO_MAX7219_DAT_bit) 
`endif			    
`ifdef NRV_IO_SPI_FLASH
   | (1 << IO_SPI_FLASH_bit) 			 
`endif			    
`ifdef NRV_MAPPED_SPI_FLASH
   | (1 << IO_MAPPED_SPI_FLASH_bit) 			 
`endif			    
`ifdef NRV_IO_SDCARD
   | (1 << IO_SDCARD_bit) 			 			 
`endif			    
`ifdef NRV_IO_BUTTONS
   | (1 << IO_BUTTONS_bit) 			 			 			 
`endif 
`ifdef NRV_IO_FGA
   | (1 << IO_FGA_CNTL_bit) | (1 << IO_FGA_DAT_bit)
`endif			 
;
   
   assign rdata = sel_memory  ? `NRV_RAM  :
		  sel_devices ?  NRV_DEVICES :
                  sel_cpuinfo ? (`NRV_FREQ << 16) | counter_width : 32'b0;
   
endmodule




/*************************************************************************************/

`ifndef NRV_RESET_ADDR
 `define NRV_RESET_ADDR 0
`endif

`ifndef NRV_ADDR_WIDTH
 `define NRV_ADDR_WIDTH 24
`endif

/*************************************************************************************/

module femtosoc(
`ifdef NRV_IO_LEDS
   output D1,D2,D3,D4,D5,
`endif	      
`ifdef NRV_IO_UART
   input  RXD,
   output TXD,
`endif	      
`ifdef NRV_SPI_FLASH
   inout spi_mosi, inout spi_miso, output spi_cs_n,
   output spi_clk, // ULX3S has spi clk shared with ESP32, using USRMCLK (below)	
`endif
`ifdef NRV_IO_BUTTONS
   `ifdef ICE_FEATHER
      input [3:0] buttons, 
   `else
      input [5:0] buttons,
   `endif		
`endif	
   input  RESET,
`ifdef NRV_IO_IRDA
   output irda_TXD,
   input  irda_RXD,
   output irda_SD,		
`endif   		
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
`ifdef ICE_STICK
  reg [11:0] reset_cnt = 0;   
`else   
  reg [15:0] reset_cnt = 0;
`endif   
  wire       reset = &reset_cnt;

/* verilator lint_off WIDTH */   
`ifdef NRV_NEGATIVE_RESET
   always @(posedge clk,negedge RESET) begin
      if(!RESET) begin
	 reset_cnt <= 0;
      end else begin
	 reset_cnt <= reset_cnt + !reset;
      end
   end
`else
   always @(posedge clk,posedge RESET) begin
      if(RESET) begin
	 reset_cnt <= 0;
      end else begin
	 reset_cnt <= reset_cnt + !reset;
      end
   end
`endif
/* verilator lint_on WIDTH */   
   
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
`ifdef NRV_MAPPED_SPI_FLASH
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
`ifdef SPI_FLASH_FAST_READ_DUAL_IO				   
      .IO({spi_miso,spi_mosi})
`else	
      .MISO(spi_miso),
      .MOSI(spi_mosi)
`endif				   
   );
`else   
   wire mem_address_is_io  =  mem_address[22];
   wire mem_address_is_ram = !mem_address[22];
`endif
      
   reg  [31:0] io_rdata; 
   wire [31:0] io_wdata = mem_wdata;
   wire        io_rstrb = mem_rstrb && mem_address_is_io;
   wire        io_wstrb = mem_wstrb && mem_address_is_io;
   wire [19:0] io_word_address = mem_address[21:2]; // word offset in io page
   wire	       io_rbusy; 
   wire        io_wbusy;
   
   assign      mem_rbusy = io_rbusy
`ifdef NRV_MAPPED_SPI_FLASH
    | mapped_spi_flash_rbusy			   
`endif 			   
    ;
   
   assign      mem_wbusy = io_wbusy; 

`ifdef NRV_IO_FGA
   wire mem_address_is_vram = mem_address[21];
`else
   parameter mem_address_is_vram = 1'b0;
`endif

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
   
`ifdef NRV_MAPPED_SPI_FLASH
   assign mem_rdata = mem_address_is_io  ? io_rdata  : 
		      mem_address_is_ram ? ram_rdata : 
		      mapped_spi_flash_rdata;   
`else   
   assign mem_rdata = mem_address_is_io ? io_rdata : ram_rdata;
`endif   
   
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


/*
 * Devices are components plugged to the IO memory bus.
 * A few words follow in case you want to write your own devices:
 *
 * Each device has one or several register(s). Each register 
 * can be optionally read or/and written.
 * - Each register is selected by a .sel_xxx signal (where xxx
 *   is the name of the register). With the 1-hot encoding that 
 *   I'm using, .sel_xxx is systematically one of the bits of the 
 *   IO word address (it is also possible to write a real
 *   address decoder, at the expense of eating-up a larger 
 *   number of LUTs).
 * - If the device requires wait cycles for writing and/or reading, 
 *   it can have a .wbusy and/or .rbusy signal(s). All the .wbusy
 *   and .rbusy signals of all the devices are ORed at the end of
 *   this file to form the .io_rbusy and .io_wbusy signals.
 * - If the device has read access, then it has a 32-bits .xxx_rdata
 *   signal, that returns 32'b0 if the device is not selected, or the
 *   read data otherwise. All the .xxx_rdata signals of all the devices
 *   are ORed at the end of this file to form the 32-bits io_rdata signal.
 * - Finally, of course, each device is plugged to some pins of the FPGA,
 *   the corresponding signals are in capital letters. 
 */   


/*********************** Hardware configuration ************/
/*
 * Three memory-mapped constant registers that make it easy for
 * client code to query installed RAM and configured devices
 * (this one does not use any pin, of course).
 * Uses some LUTs, a bit stupid, but more comfortable, so that
 * I do not need to change the software on the SDCard each time 
 * I test a different hardware configuration.
 */
`ifdef NRV_IO_HARDWARE_CONFIG   
wire [31:0] hwconfig_rdata;
HardwareConfig hwconfig(
   .clk(clk),			
   .sel_memory(io_word_address[IO_HW_CONFIG_RAM_bit]),
   .sel_devices(io_word_address[IO_HW_CONFIG_DEVICES_bit]),
   .sel_cpuinfo(io_word_address[IO_HW_CONFIG_CPUINFO_bit]),			
   .rdata(hwconfig_rdata)			 
);
`endif
   
/*********************** Four LEDs ************************/
`ifdef NRV_IO_LEDS
   wire [31:0] leds_rdata;
   LEDDriver leds(
`ifdef NRV_IO_IRDA
      .irda_TXD(irda_TXD),
      .irda_RXD(irda_RXD),
      .irda_SD(irda_SD),		
`endif		  
      .clk(clk),
      .rstrb(io_rstrb),		  
      .wstrb(io_wstrb),			
      .sel(io_word_address[IO_LEDS_bit]),
      .wdata(io_wdata),		  
      .rdata(leds_rdata),
      .LED({D4,D3,D2,D1})
   );
`endif  

/********************** UART ****************************************/
`ifdef NRV_IO_UART

 // Internal wires to connect IO buffers to UART
 wire RXD_internal;
 wire TXD_internal;

 
 // For other boards, we directly connect RXD and TXD to the UART (but we may need
 // to latch).
 `ifndef UART_IO_BUFFER
   assign RXD_internal = RXD;
   assign TXD = TXD_internal;
 `endif

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
`else
   wire uart_brk = 1'b0;
`endif 


/********************* Buttons  *************************************/
/*
 * Directly wired to the buttons.
 */
`ifdef NRV_IO_BUTTONS
   wire [31:0] buttons_rdata;
   Buttons buttons_driver(
      .sel(io_word_address[IO_BUTTONS_bit]),
      .rdata(buttons_rdata),
      .BUTTONS(buttons)		   
   );
`endif
   
/************** io_rdata, io_rbusy and io_wbusy signals *************/

/*
 * io_rdata is latched. Not mandatory, but probably allow higher freq, to be tested.
 */
always @(posedge clk) begin
   io_rdata <= 0
`ifdef NRV_IO_HARDWARE_CONFIG	       
            | hwconfig_rdata
`endif	       
`ifdef NRV_IO_LEDS      
	    | leds_rdata
`endif
`ifdef NRV_IO_UART
	    | uart_rdata
`endif	    
`ifdef NRV_IO_SDCARD
	    | sdcard_rdata
`endif
`ifdef NRV_IO_BUTTONS
	    | buttons_rdata
`endif
`ifdef NRV_IO_FGA
	    | FGA_rdata
`endif
	    ;
end

   // For now, we got no device that has
   // blocking reads (SPI flash blocks on
   // write address and waits for read data).
   assign io_rbusy = 0 ; 

   assign io_wbusy = 0
`ifdef NRV_IO_SSD1351_1331
	| SSD1351_wbusy
`endif
`ifdef NRV_IO_MAX7219
	| max7219_wbusy
`endif		   
`ifdef NRV_IO_SPI_FLASH
        | spi_flash_wbusy
`endif		   
; 

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
`ifdef NRV_INTERRUPTS
    .interrupt_request(1'b0),	      
`endif     
    .reset(reset && !uart_brk)
  );

`ifdef NRV_IO_LEDS  
   assign D5 = error;
 `ifdef FOMU
    SB_RGBA_DRV #(
        .CURRENT_MODE("0b1"),       // half current
        .RGB0_CURRENT("0b000011"),  // 4 mA
        .RGB1_CURRENT("0b000011"),  // 4 mA
        .RGB2_CURRENT("0b000011")   // 4 mA
    ) RGBA_DRIVER (
        .CURREN(1'b1),
        .RGBLEDEN(1'b1),
        .RGB0PWM(D1), 
        .RGB1PWM(D2), 
        .RGB2PWM(D3), 
        .RGB0(rgb0),
        .RGB1(rgb1),
        .RGB2(rgb2)
    );
 `endif
`endif
   
endmodule

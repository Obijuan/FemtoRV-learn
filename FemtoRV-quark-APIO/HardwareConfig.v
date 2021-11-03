`define NRV_COUNTER_WIDTH 24        // Number of bits in cycles counter

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


localparam counter_width = `NRV_COUNTER_WIDTH;

`define NRV_IO_LEDS          // Mapped IO, LEDs D1,D2,D3,D4 (D5 is used to display errors)
`define NRV_IO_UART          // Mapped IO, virtual UART (USB)
`define NRV_MAPPED_SPI_FLASH // SPI flash mapped in address space. Use with MINIRV32 to run code from SPI flash.
`define NRV_RAM 6144 // default for ICESTICK (cannot do more !)
`define NRV_FREQ 50                 // Validated at 50 MHz on the IceStick. Can overclock to 70 MHz.

   
// configured devices
localparam NRV_DEVICES = 0
`ifdef NRV_IO_LEDS
   | (1 << IO_LEDS_bit)			 
`endif			    
`ifdef NRV_IO_UART
   | (1 << IO_UART_DAT_bit) | (1 << IO_UART_CNTL_bit)
`endif			    		    		    
`ifdef NRV_MAPPED_SPI_FLASH
   | (1 << IO_MAPPED_SPI_FLASH_bit) 			 
`endif			 
;
   
   assign rdata = sel_memory  ? `NRV_RAM  :
		  sel_devices ?  NRV_DEVICES :
                  sel_cpuinfo ? (`NRV_FREQ << 16) | counter_width : 32'b0;
   
endmodule
`ifndef SPI_FLASH_DUMMY_CLOCKS
 `define SPI_FLASH_DUMMY_CLOCKS 8
`endif

module MappedSPIFlash( 
    input wire 	       clk,          // system clock
    input wire 	       rstrb,        // read strobe		
    input wire [19:0]  word_address, // address to be read

		      
    output wire [31:0] rdata, // data read
    output wire        rbusy, // asserted if busy receiving data 

    output wire        CLK,  // clock
    output reg 	       CS_N, // chip select negated (active low)		
    inout wire [1:0]   IO    // two bidirectional IO pins
);

   reg [4:0]  clock_cnt; // send/receive clock, 2 bits per clock (dual IO)
   reg [39:0] shifter;   // used for sending and receiving

   reg 	      dir; // 1 if sending, 0 otherwise

   wire       busy      = (clock_cnt != 0);
   wire       sending   = (dir  && busy);
   wire       receiving = (!dir && busy);
   assign     rbusy     = !CS_N; 

   // The two data pins IO0 (=MOSI) and IO1 (=MISO) used in bidirectional mode.
   reg IO_oe = 1'b1;
   wire [1:0] IO_out = shifter[39:38];
   wire [1:0] IO_in  = IO;
   assign IO = IO_oe ? IO_out : 2'bZZ;
   
   initial CS_N = 1'b1;
   assign  CLK  = !CS_N && !clk; 

   // since least significant bytes are read first, we need to swizzle...
   assign rdata={shifter[7:0],shifter[15:8],shifter[23:16],shifter[31:24]};

   // Duplicates the bits (used because when sending command, dual IO is
   // not active yet, and I do not want to have a separate shifter for
   // the command and for the args...).
   function [15:0] bbyyttee;
      input [7:0] x;
      begin
	 bbyyttee = {
	     x[7],x[7],x[6],x[6],x[5],x[5],x[4],x[4],
	     x[3],x[3],x[2],x[2],x[1],x[1],x[0],x[0]
	 }; 	 
      end
   endfunction

   always @(posedge clk) begin
      if(rstrb) begin
	 CS_N  <= 1'b0;
	 IO_oe <= 1'b1;
	 dir   <= 1'b1;
	 shifter <= {bbyyttee(8'hbb), 2'b00, word_address[19:0], 2'b00};
	 clock_cnt <= 5'd20 + `SPI_FLASH_DUMMY_CLOCKS; // cmd: 8 clocks  address: 12 clocks  + dummy clocks
      end else begin
	 if(busy) begin
	    shifter <= {shifter[37:0], (receiving ? IO_in : 2'b11)};
	    clock_cnt <= clock_cnt - 5'd1;	    
	    if(dir && clock_cnt == 1) begin
 	       clock_cnt <= 5'd16; // 32 bits, 2 bits per clock
	       IO_oe <= 1'b0;
	       dir   <= 1'b0;
	    end 
	 end else begin
	    CS_N <= 1'b1;
	 end
      end
   end
endmodule
 
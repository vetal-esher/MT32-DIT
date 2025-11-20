//Roland MT-32 parallel DAC data converter to 16 bit right justified for Digital Audio Transmitters

module dac_decoder (
        input wire rst_n,		//reset signal
        input rev_sw,           	//reverb switch
        input clk_inh,			//256kHz INH clk input
        input [2:0] ch_id,		//cd4051 sample/hold controls a/b/c
        input signed [15:0] dac,	//parallel input from dac
        input drq,                 	//data request
        output reg dtr,             	//data ready flag
        output reg [31:0] data		//32 bit dac output
);
reg signed [15:0] lsyn1, lsyn2, rsyn1, rsyn2, rrev;	//channels from LA32 and Reverb ICs
reg signed [15:0] left,right;
reg signed [16:0] l,r;

initial begin
    data<=0; rrev<=0; rsyn1<=0; lsyn2<=0; rsyn2<=0; 
    l<=0; r<=0; left<=0; right<=0; dtr<=0;
end

localparam signed [15:0] OFFSET = 16'd8192; //Digital DC offset fix

always  @(negedge clk_inh) begin
	if (!rst_n) begin
		data<=0; dtr<=0;
	end else begin
	case (ch_id)
     		7 : begin // RSYN1
			rsyn1<=dac; dtr<=1;
			left <= l[15:0]-OFFSET; right <= r[15:0]-OFFSET;
		    end 
		6 : begin rsyn2<=dac; dtr<=0; end // RSYN2
		5 : begin data<={left,right}; dtr<=0; end // empty
		4 : begin dtr<=1; end // empty
		3 : begin lsyn1<=dac; dtr<=1; end // LSYN1
		2 : begin lsyn2<=dac; dtr<=1; end // LSYN2
		1 : begin rrev<=dac;  dtr<=1; end // RREV
		0 : begin dtr<=0; // LREV
			if (!rev_sw) begin  l<=lsyn1; r<=rsyn1;  end else 
			begin l<=lsyn1+lsyn2+dac; r<=rsyn1+rsyn2+rrev; end
 	     	end 
	endcase
	end
end
endmodule

module i2s_serializer (
        input wire rst_n,		//reset signal
        input mclk,			//master clock 16.384MHz
        input [31:0] data,		//input data 
        input dtr,              	//data ready flag
        output reg drq, 		//data request
        output reg sdata,		//i2s sdata output
        output reg wclk,		//i2s word select lrck output mclk/512 = 32kHz
        output bck			//i2s bit clock output //16bit * 2 * 32000 = 1.024 MHz (16.384/16)
);
reg [31:0] mclk_counter;       		//32bit counter
wire bck_int = mclk_counter[3];    	//OSC divide
BUFG bck_bufg_inst (.I(bck_int), .O(bck));
reg [31:0] data_buf;	    		//i2s output buffer 
reg [31:0] data_int;	    		//i2s input buffer 
reg [4:0] cbit;				        //current bit counter

always  @(posedge mclk) begin			
	if (!rst_n) begin mclk_counter<=0; end 
	else begin 
		mclk_counter<=mclk_counter+1;
        	if (dtr==1 && drq==0) begin data_int<=data; end
	end
    
end

always  @(negedge bck_int) begin
	if (!rst_n) begin 
		cbit<=0; wclk<=0; data_buf<=0;
	end else begin 
		if (wclk==0) begin sdata<=data_buf[31-cbit]; end 	//LSYN send
		else if (wclk==1) begin sdata<=data_buf[15-cbit]; end	//RSYN send

		cbit<=cbit+4'b01;

		if (cbit==15 && wclk==0) begin //LSYN end
			cbit<=0; wclk<=1; drq<=0; 
		end		        	
		else if (cbit==15 && wclk==1) begin //RSYN end, new buffer read
			cbit<=0; wclk<=0; drq<=1; data_buf<=data_int; 
		end else begin drq<=0; end
 	end
end
endmodule


module top 	(
        input mclk,             //master clock 16.384MHz //pin 51
        input clk_inh,          //256kHz INH clk input   //pin 53
        input [2:0] ch_id,      //cd4051 a/b/c 128/64/32kHz //pin a 77 b 76 c 48
        input signed [15:0] dac,//parallel input from dac
        input sys_rst_n,        //reset input
        input rev_sw,           //reverb switch
        output wire drq,        //data request //pin 69
        output wire dtr,        //data write   //pin 68
        output sdata,           //16bit RJ sdata output  //pin32
        output wire wclk,       //word select lrck output 32kHz //pin31
        output wire bck         //bit clock output 1024MHz //pin49
);
wire [31:0] data;

dac_decoder dac1(
    .clk_inh(clk_inh),.ch_id(ch_id),.dac(dac),.data(data),.rst_n(sys_rst_n),.rev_sw(rev_sw),.drq(drq),.dtr(dtr)
);
i2s_serializer ser1 (
	.mclk(mclk),.sdata(sdata),.wclk(wclk),.bck(bck),.data(data),.rst_n(sys_rst_n),.drq(drq),.dtr(dtr)
);

endmodule

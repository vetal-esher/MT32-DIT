module top 	(
        input mclk,             //master clock //pin 51
        input clk_inh,          //256kHz INH clk input //pin 53
        input [2:0] ch_id,      //cd4051 sample/hold controls a/b/c 128/64/32kHz //pin a 77 b 76 c 48
        input signed [15:0] dac,       //parallel input from dac
        input sys_rst_n,        //reset input
        input rev_sw,           //reverb switch
        output wire dtw,        //data write flag
        output wire dtr,        //data ready //pin68
        output wire drq,        //data request //pin69
        output sdata,           //16bit i2s sdata output  //pin32
        output wire wclk,       //i2s word select lrck output 32kHz //pin31
        output wire bck         //i2s bit clock output 1024MHz //pin49
);
wire [31:0] data;

dac_decoder dac1(
    .clk_inh(clk_inh),.ch_id(ch_id),.dac(dac),.data(data),.rst_n(sys_rst_n),.rev_sw(rev_sw),.dtr(dtr),.drq(drq),.dtw(dtw)
);
i2s_serializer ser1 (
	.mclk(mclk),.sdata(sdata),.wclk(wclk),.bck(bck),.data(data),.rst_n(sys_rst_n),.drq(drq)
);
endmodule

module i2s_serializer (
        input wire rst_n,		//reset signal
        input mclk,			//master clock 16.384MHz
        input [31:0] data,		//input data 
        output reg drq, 		//data request
        output reg sdata,		//i2s sdata output
        output reg wclk,		//i2s word select lrck output mclk/512 = 32kHz
        output bck			//i2s bit clock output //16bit * 2 * 32000 = 1.024 MHz (16.384/16)
);
reg [31:0] mclk_counter;       		//32bit counter
assign bck=mclk_counter[3];     	//OSC divide
reg [31:0] data_buf;			//i2s output buffer 
reg [4:0] cbit;				//current bit counter
reg sync;
			
initial begin
	mclk_counter<=0; cbit<=0; wclk<=0; data_buf<=0; sync<=0;
end


always  @(posedge mclk,negedge rst_n) begin			
	if (!rst_n) begin mclk_counter<=0; sync<=0; end 
	else begin 
		mclk_counter<=mclk_counter+1;
	end
    
end

always  @(negedge bck) begin
	if (wclk==0) begin sdata<=data_buf[31-cbit]; end 				//LSYN send
	else if (wclk==1) begin sdata<=data_buf[15-cbit]; end				//RSYN send

    cbit<=cbit+4'b01;

	if (cbit==15 && wclk==0) begin cbit<=0; wclk<=1; drq<=0; end				//LSYN1 end
	else if (cbit==15 && wclk==1) begin cbit<=0; wclk<=0; drq<=1; data_buf<=data; end 	//RSYN1 end, new buffer read
    else begin drq<=0; end

end
endmodule


module dac_decoder (
        input wire rst_n,		//reset signal
        input rev_sw,           	//reverb switch
        input clk_inh,			//256kHz INH clk input
        input [2:0] ch_id,		//cd4051 sample/hold controls a/b/c
        input signed [15:0] dac,	//parallel input from dac
        input drq,                  	//data request
        output reg dtw,         	//data write flag
        output reg [31:0] data,		//32 bit dac output
        output reg dtr			//data ready flag for FIFO
);
reg signed [15:0] lrev;			//LREV  ch0
reg signed [15:0] rsyn2;		//RSYN2 ch6
reg signed [15:0] lsyn2;		//LSYN2 ch2
reg signed [15:0] rrev;			//RREV  ch1
reg signed [15:0] rsyn1;		//RSYN1 ch7
reg signed [15:0] lsyn1;		//LSYN1 ch3
reg signed [16:0] l;
reg signed [16:0] r;
reg signed [15:0] left;
reg signed [15:0] right;
reg signed [15:0] offset;

initial begin
    data<=0; lrev<=0; rrev<=0; lsyn1<=0; rsyn1<=0; lsyn2<=0; rsyn2<=0; dtr<=0;
    l<=0; r<=0; left<=0; right<=0; offset<=16384; 
end

//assign offset=16384;
assign offset=16384;

always  @(negedge clk_inh,negedge rst_n) begin
	if (!rst_n) begin
		dtr<=0; data<=0;
	end 
	else begin
	case (ch_id)
		4 : begin dtr<=0; dtw<=0; left[15:0]<= l[15:0]; right[15:0]<= r[15:0]; end // empty
		0 : begin dtr<=0; dtw<=0; lrev<=dac;  end // LREV
		6 : begin dtr<=0; dtw<=0; rsyn2<=dac; end // RSYN2
		2 : begin dtr<=0; dtw<=0; lsyn2<=dac; end // LSYN2
		5 : begin dtr<=1; dtw<=1; data<={left,right};  end // empty
		1 : begin dtr<=0; dtw<=0; rrev<=dac; end // RREV
		7 : begin dtr<=0; dtw<=0; rsyn1<=dac; end // RSYN1
		3 : begin dtr<=0; dtw<=0; lsyn1<=dac;     // LSYN1
              if (!rev_sw) begin l<=dac; r<=rsyn1; end 
              else begin l<=dac+lrev+lsyn2; r<=rsyn1+rrev+rsyn2; end
            end 
	endcase
	end
end
endmodule
//Roland MT-32 parallel DAC data converter to 16 bit right justified for Digital Audio Transmitters

module dac_decoder (
        input wire rst_n,		//reset signal
        input rev_sw,           	//reverb switch
        input clk_inh,			//256kHz INH clk input
        input [2:0] ch_id,		//cd4051 sample/hold controls a/b/c
        input [15:0] dac,	    	//parallel input from dac
        input drq,                 	//data request
        output reg [31:0] data		//32 bit dac output
);
reg [15:0] lsyn1, lsyn2, lrev, rsyn1, rsyn2, rrev;	//channels from LA32 and Reverb ICs
reg [15:0] left,right;
reg [16:0] l,r;
reg frame_sent;

initial begin
    data<=0; lrev<=0; rrev<=0; rsyn1<=0; lsyn2<=0; rsyn2<=0; 
    l<=0; r<=0; left<=0; right<=0; frame_sent<=0;
end

//localparam [15:0] OFFSET = 16'd24536; //Digital DC offset fix
localparam [15:0] OFFSET = 16'd16344; //Digital DC offset fix

always  @(negedge clk_inh,negedge rst_n) begin
	if (!rst_n) begin
		data<=0; frame_sent<=0;
	end else begin
	case (ch_id)
		4 : begin // empty
			if (!rev_sw) begin 
				l<=lsyn1; r<=rsyn1; 
			end else begin 
				l<=lsyn1+lsyn2+lrev; r<=rsyn1+rsyn2+rrev; 
			end
	            end 
		0 : begin // LREV
			left <= l-OFFSET; right <= r-OFFSET;
			frame_sent<=0; 
			lrev<=dac;
		    end 
		6 : begin // RSYN2
			rsyn2<=dac; 
			if (!drq) begin data<={left,right}; frame_sent<=1; end
		    end 
		2 : begin // LSYN2
			lsyn2<=dac; 
			if (!drq && !frame_sent) begin data<={left,right}; frame_sent<=1; end 
		    end 
		5 : begin // empty
			if (!drq && !frame_sent) begin data<={left,right}; frame_sent<=1; end 
		    end
		1 : begin rrev<=dac;  end // RREV
		7 : begin rsyn1<=dac; end // RSYN1
		3 : begin lsyn1<=dac; end // LSYN1
	endcase
	end
end
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
wire bck_int = mclk_counter[3];     //OSC divide
BUFG bck_bufg_inst (.I(bck_int), .O(bck));
reg [31:0] data_buf;	    		//i2s output buffer 
reg [4:0] cbit;				        //current bit counter

always  @(posedge mclk) begin			
	if (!rst_n) begin mclk_counter<=0; end 
	else begin 
		mclk_counter<=mclk_counter+1;
	end
    
end

always  @(negedge bck_int) begin
	if (!rst_n) begin 
		cbit<=0; wclk<=0; data_buf<=0;
	end else begin 

		if (wclk==0) begin sdata<=data_buf[31-cbit]; end 	//LSYN send
		else if (wclk==1) begin sdata<=data_buf[15-cbit]; end	//RSYN send

		cbit<=cbit+4'b01;

		if (cbit==15 && wclk==0) begin cbit<=0; wclk<=1; drq<=0; end		        	//LSYN end
		else if (cbit==15 && wclk==1) begin cbit<=0; wclk<=0; drq<=1; data_buf<=data; end 	//RSYN end, new buffer read
		else begin drq<=0; end

	end
end
endmodule


module top 	(
        input mclk,             //master clock 16.384MHz //pin 51
        input clk_inh,          //256kHz INH clk input   //pin 53
        input [2:0] ch_id,      //cd4051 sample/hold controls a/b/c 128/64/32kHz //pin a 77 b 76 c 48
        input [15:0] dac,       //parallel input from dac
        input sys_rst_n,        //reset input
        input rev_sw,           //reverb switch
        output wire drq,        //data request //pin69
        output sdata,           //16bit RJ sdata output  //pin32
        output wire wclk,       //word select lrck output 32kHz //pin31
        output wire bck         //bit clock output 1024MHz //pin49
);
wire [31:0] data;

dac_decoder dac1(
    .clk_inh(clk_inh),.ch_id(ch_id),.dac(dac),.data(data),.rst_n(sys_rst_n),.rev_sw(rev_sw),.drq(drq)
);
i2s_serializer ser1 (
	.mclk(mclk),.sdata(sdata),.wclk(wclk),.bck(bck),.data(data),.rst_n(sys_rst_n),.drq(drq)
);

endmodule

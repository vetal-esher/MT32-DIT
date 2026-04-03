//Roland MT-32 parallel DAC data converter to 16 bit right justified for Digital Audio Transmitters

module i2s_serializer (
        input wire rst_n,		//reset signal
        input mclk,			//master clock 16.384MHz
        input rev_sw,           	//reverb switch
        //input chorus_sw,           	//chorus switch
        input clk_inh,			//256kHz INH clk input
        input [2:0] ch_id,		//cd4051 sample/hold controls a/b/c
        input signed [15:0] dac,	//parallel input from dac
        output reg dtr,      		//data ready flag
        output reg skip,        	//data skipped flag
        output reg drq, 		//data request
        output reg sdata,		//i2s sdata output
        output reg wclk,		//i2s word select lrck output mclk/512 = 32kHz
        output bck			//i2s bit clock output //16bit * 2 * 32000 = 1.024 MHz (16.384/16)
);
reg [4:0] mclk_counter;       		//bit counter
wire bck_int = mclk_counter[3];     	//OSC divide
BUFG bck_bufg_inst (.I(bck_int), .O(bck));
reg signed [15:0] lsyn1, lsyn2, rsyn1, rsyn2, rrev, l, r;
//reg signed [15:0] left, right;
reg [31:0] data;    	    		//dac 
reg [31:0] data_buf;	    		//i2s output buffer 
reg [31:0] data_int;	    		//i2s input buffer 
reg [3:0] cbit;				//current bit counter

always  @(posedge mclk) begin			
	if (!rst_n) begin 
        mclk_counter<=0; skip<=0; dtr<=0; l<=0; r<=0;
    end 
	else begin 
		mclk_counter<=mclk_counter+5'b01;
        if (dtr==1 && drq==0) begin data_int<=data; end
        if (dtr==0 && drq==1) begin skip<=1; end else begin skip<=0; end
        if (clk_inh==0) begin
            case (ch_id)
                7 : begin // RSYN1
                    rsyn1<=dac; dtr<=0;
                    data<={l,r}; 
                    end 
                6 : begin // RSYN2
                    rsyn2<=dac; dtr<=0;                   
                    end
                5 : begin // empty                    
                    dtr<=1;
                    end 
                4 : begin // empty
                    dtr<=1;
                    end 
                3 : begin lsyn1<=dac; dtr<=1; end // LSYN1
                2 : begin lsyn2<=dac; dtr<=1; end // LSYN2
                1 : begin rrev<=dac; dtr<=1; end  // RREV
                0 : begin dtr<=1; 		  // LREV
                    if (!rev_sw) begin  l<=lsyn1; r<=rsyn1;  end else 
                    begin l<=lsyn1+lsyn2+dac; r<=rsyn1+rsyn2+rrev; end
                    end 
            endcase
        end
	end
    
end

always  @(negedge bck_int) begin
	if (!rst_n) begin 
		cbit<=0; wclk<=0; data_buf<=0; drq<=0;  
	end else begin 
		if (wclk==0) begin sdata<=data_buf[31-cbit]; end 	//LSYN send
		else if (wclk==1) begin sdata<=data_buf[15-cbit]; end	//RSYN send

		cbit<=cbit+4'b01;

		if (cbit==15 && wclk==0) begin cbit<=0; wclk<=1; drq<=0; end  //LSYN end
		else if (cbit==15 && wclk==1) begin 
	            cbit<=0; wclk<=0; drq<=1; data_buf<=data_int;
        	end 	//RSYN end, new buffer read
		else begin drq<=0; end

	end
end
endmodule


module top 	(
        input mclk,             //master clock 16.384MHz //pin 51
        input clk_inh,          //256kHz INH clk input   //pin 53
        input [2:0] ch_id,      //cd4051 sample/hold controls a/b/c 128/64/32kHz //pin a 77 b 76 c 48
        input signed [15:0] dac,//parallel input from dac
        input sys_rst_n,        //reset input
        input rev_sw,           //reverb switch
        //input chorus_sw,      //chorus switch
        output wire drq,        //data request //pin69
        output wire dtr,        //data ready //pin 57
        output wire skip,       //data skipped
        output sdata,           //16bit RJ sdata output  //pin32
        output wire wclk,       //word select lrck output 32kHz //pin31
        output wire bck         //bit clock output 1.024MHz //pin49
);


i2s_serializer ser1 (
    .clk_inh(clk_inh),.ch_id(ch_id),.dac(dac),.rev_sw(rev_sw), //.chorus_sw(chorus_sw),
	.mclk(mclk),.sdata(sdata),.wclk(wclk),.bck(bck),.rst_n(sys_rst_n),.drq(drq),.dtr(dtr),.skip(skip)
);

endmodule



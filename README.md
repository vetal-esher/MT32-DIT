# MT32-DIT
<h3>Adding digital output to legendary Roland MT-32</h3>
<p>
This project can be considered part #2 of the digitalization of old synthesizers. In the first part I described <a href="https://github.com/vetal-esher/18bit-DIT">how you can add a  digital outpu</a>t to almost any synthesizer (where the DAC circuit uses standard L/R combined I2S) by using the AK4103AVF</p>

<p>
Roland MT-32, familiar to old gamers in the 90s and very rare now, is an even older device that uses a parallel DAC scheme that was 
quite common in Roland's D-series, which does not just convert the final stereo stream in-line, but also simultaneously performs 
the services of a DAC for the reverb IC.</p>

<h3>Digging demuxer logic</h4>

<p><img src="images/mt32-4051.jpg"></p>

<p>
It turns out that we do not have direct access to the digital stream containing the final audio data. The PCM54HP receives a stream 
that sequentially contains not only clean left and right channels, but also separate reverb data for the left and right channels. 
It looks something like this (all frames are 16bit, order is assumed): [RSYN1][LSYN1][REV R][REV L][RSYN2][LSYN2][RSYN1][LSYN1][REV R][REV L][RSYN2] [LSYN2] etc.</p>
<p>
The advantage of a parallel DAC is that it works instantly, i.e. there is no delay at all in taking the current values 
from the (essentially) resistor assembly and the next moment doing the task of transforming a completely different picture. 
The widely known CD4051 is engaged in demultiplexing all this porridge of audio data. Channel switching in the CD4051 is carried out 
through the control lines mixed from LA and Reverb chips SH1 SH2 SH2 (SH - Sample / Hold), as well as the INH line, which turns on and off 
all channels. At the output of the demuxer, three pairs of analog channels are formed, which are then mixed and undergo final 
processing in a low-pass filter. The LP filter should have a flat amplitude response in the 0-20kHz range and a high attenuation above 20kHz.
</p>

<p><img src="images/schematic.png"></p>

<p>
Bit depth and sampling frequency of MT-32 according to the declared characteristics - 15bit 32kHz. In the first version of MT-32 
(the so-called "old"), the last 16th bit at the PCM54HP input is shorted to ground, and for that (15bit) reason the 14th bit fell out 
in the data bus itself (counting from zero). However, for us, the frame width will always be 16 bits (the 2nd MT-32 version has full 16bit bus). Theoretically, the channel  switching frequency 0-1-2-3-4-5-6-7 each time triggers a 0/1 state change in control signal A, so you can 
expect 128kHz on this line,  and 64 on lines B and C, and 32kHz respectively. But we don't know the order of the frames. Even if we 
sequentially record all the states of the parallel bus, it will be useless if we do not know the order of switching ABC. In practice, 
without a three-channel oscilloscope, you can try to catch the states of at least two of the three lines (A and C), and then record 
the AB and BC, A and INH sequences in order to further bring the picture into one.
</p>
<p><img src="images/INH-A-B-C.png"></p>
<p>

So now we know the frame order: [L REV][RSYN2][LSYN2][R REV][RSYN1][LSYN1], [L REV][RSYN2][LSYN2][R REV][RSYN1][LSYN1] .. etc. 
If you listen to these pins in analog, it becomes clear that SYN1 is a clean signal, REV is a reverb return. SYN2 appears to be 
analog as well, but too quiet to be recorded legibly; but since SYN2 is also mixed into the final mix, we'll do that too. 
By the way, if you look at the unused outputs of the CD4051 CH4 and CH5, there will be [almost] crisp 32kHz:

<p float="left"><img src="images/CH4.png" width="50%"><img src="images/CH5.png" width="50%"></p>

<p>The INH control signal operates at a frequency of 256kHz, which means we will need to read all ports at this frequency. 
Disabling all channels is necessary so that there is no false triggering on rising edges @ABC states, when INH=1 tells us that 
we don’t need to send anything to serial. With INH=0, we must read the bus, and depending on the states of ABC, scatter it to 
the appropriate output. Ideally, we need to define the beginning of frame (we take the highest INH peak for the reference frame)
and mix all L / R frames into two final ones. But for the test, you can start by sending two frames with a clean non-reverberated 
information (RSYN1, LSYN1). At first I thought to bother with the sequence' start detection, but then I omitted this part, because,
even if the logic begins to run in the middle, defining LSYN1 as the end of the sequence we will reset the counters and then start 
working in the correct order. The logic in this case will look something like this (I will use a pseudo-language here with a syntax 
that is clear to everyone):</p>

<pre>
(R,L)=(0,0);
(FLAG_RSYN1,FLAG_LSYN1,FLAG_RSYN2,FLAG_LSYN2,FLAG_RREV,FLAG_LREV)=(0,0,0,0,0,0);
(RSYN1,LSYN1,RSYN2,LSYN2,RREV,LREV)=(0,0,0,0,0,0);
while (256kHz_cycle) {
	input=read(PCM54_parallel);
	A=read(CD4051_A); B=read(CD4051_B); C=read(CD4051_C); INH=read(CD4051_INH);

	#INH==0 enables output
	if (INH==0) {
		if (A==1 && B==1 && C==0) {
			RSYN2=input; FLAG_RSYN2=1; #RSYN2
		}
		elsif (A==0 && B==1 && C==0) {
			LSYN2=input; FLAG_LSYN2=1; #LSYN2
		}
		elsif (A==0 && B==0 && C==1) {
			RREV=input; FLAG_RREV=1;   #RREV
		}
		elsif (A==0 && B==0 && C==0) {
			LREV=input; FLAG_LREV=1;   #LREV
		}
		elsif (A==1 && B==1 && C==1) {
			RSYN1=input; FLAG_RSYN1=1; #RSYN1
		}
		elsif (A==0 && B==1 && C==1) {
			LSYN1=input; 		   #LSYN1 this is the last channel in frame
			(FLAG_RSYN1,FLAG_LSYN1,FLAG_RSYN2,FLAG_LSYN2,FLAG_RREV,FLAG_LREV)=(1,1,1,1,1,1);
		}

		if (FLAG_RSYN1==1 && FLAG_LSYN1==1 && FLAG_RSYN2==1 && FLAG_LSYN2==1 && FLAG_RREV==1 && FLAG_LREV==1) {

			#in merge there will be magic
			L=merge(LSYN1,LSYN2,LREV);
			R=merge(RSYN1,RSYN2,RREV);
			write_serial(R,L); 

			#reset channel flags
			(FLAG_RSYN1,FLAG_LSYN1,FLAG_RSYN2,FLAG_LSYN2,FLAG_RREV,FLAG_LREV)=(0,0,0,0,0,0);
		}
	}
}
</pre>

<h3>Hardware part</h3>

<p>Schematically, the plan of the entire project was drawn like this:</p>
<p><img src="images/profit.png"></p>
<p>
There is only one magic figure involved in this plan, and here, I will honestly say, giant constructions from a heap of logic come to mind, which must perform the task of mixing digital streams. I was told that I should stop doing garbage and learn a programmable FPGA. All of the PCM and INH/A/B/C signals are CMOS-level, so we need to convert them to TTL by CD4050B. By the way, we will get fixed levels of INH after CD4050:
</p>
<p><img src="images/after4050.png"></p>
<h4>DIT</h4>
<p>
Since we are dealing with 16 bits, a large number of DITs can be used, as they all work at least with 16-bit RJ. For these purposes, I chose DIT4192, because I have it was already available after experimenting with the 18-bit DIT. Settings are typical:
<table border="1">
<tr><th colspan="2">DIT4192 Hardware mode</th></tr>
<tr><td>Mode operation</td><td>Slave (SYNC and SCLK are inputs)</td></tr>
<tr><td>Format</td><td>16-Bit Right-Justified</td></tr>
<tr><td>Sampling frequency</td><td>32kHz</td></tr>
<tr><td>Master clock</td><td>16.384MHz (512*fs)</td></tr>
<tr><td>Bit clock</td><td>1.024MHz (16*2*32KHz)</td></tr>
</table>
</p>

<p><img src="images/dit-schematic.jpg"></p>

<h3>Magic part</h3>
<p>The FPGA <a href="https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html">Tang Nano 9K</a> was chosen for the magic part, so the "profit" plan was drawn:</p>
<p><img src="images/profit2.png"></p>
<p>And then the complete schematic of the "magic" part was done. Note the I2S connector, you can completely skip DIT4192 in schematic and use your favorite external DIT, or even just transport I2S to I2S receiver.</p>
<p><img src="images/9k-schematic.jpg"></p>

<h3>Making prototypes</h3>
<p>I started with sandwich-like breadboard, trying to split the CMOS-TTL logic from TangNano. Different methods, using couple of variants (voltage dividers) and CD4050 were tried..</p>
<p float="left"><img src="images/proto1.jpg" width="50%"><img src="images/proto2.jpg" width="50%"></p>

.. and then, when i finally decided to use CD4050, i have projected the PCB. The PCBs were made quick at PCBway factory, and i must say their quality is awesome, even for such pet projects like mine :) 

<p float="left"><img src="images/pcbway1.jpg" width="50%"><img src="images/pcbway2.jpg" width="50%"></p>

<p>Final design assumes, that the original PCM54HP will be desoldered from MT-32 mainboard, and then socketed on second footprint right on DIT pcb. After that, MT32-DIT can be soldered or socketed on MT-32 mainboard. But for now, we'll just put on the DIT board right over PCM54HP IC.</p>

<h3>Learning VERILOG</h3>
<p>I did not have any experience in designing FPGA projects, and did not knew about verilog language anything. But it appeared, that my pseudo-language logic described above is almost verilog-like! So, after few weeks, the very first working code was written:
	
<pre>
module top (
        input mclk,             //master clock //pin 51
        input clk_inh,          //256kHz INH clk input //pin 53
        input [2:0] ch_id,      //cd4051 sample/hold controls a/b/c 128/64/32kHz //pin a 77 b 76 c 48
        input [15:0] dac,       //parallel input from dac
	input sys_rst_n,        //reset input
	output wire dtr,        //data ready flag //pin54
        output sdata,           //16bit i2s sdata output  //pin 49
        output wire wclk,       //i2s word select lrck output 32kHz //pin 31
        output wire bck         //i2s bit clock output 1024MHz //pin32
);

wire [31:0] data;

dac_decoder dac1(
	.clk_inh(clk_inh),.ch_id(ch_id),.dac(dac),.data(data),.rst_n(sys_rst_n),.dtr(dtr)
);

i2s_serializer ser1 (
	.mclk(mclk),.sdata(sdata),.wclk(wclk),.bck(bck),.data(data),.rst_n(sys_rst_n)
);

endmodule


module i2s_serializer (
        input mclk,             	//master clock 16.384MHz
	input [31:0] data,		//input channels register 
	input wire rst_n,		//reset button	
	output reg sdata,   	    	//i2s sdata output
        output reg wclk,        	//i2s word select lrck output mclk/512 = 32kHz
        output wire bck         	//[3] bit'mclk. i2s bit clock output 
					//16bit * 2 * 32000 = 1.024 MHz (16.384/16)
);
reg [31:0] mclk_counter;       		//32bit counter
assign bck=mclk_counter[3];     	//1.024MHz divide
reg [31:0] data_buf;			//i2s output buffer 
reg [4:0] cbit;				//0-15 current bit counter
			
initial begin
	mclk_counter<=0; cbit<=0; wclk<=0; data_buf<=0;
end

always  @(posedge mclk,negedge rst_n) begin
	if(!rst_n) begin mclk_counter<=0; end 
	else begin mclk_counter<=mclk_counter+1; end
end

//i2s WCLK=0 left, =1 right
always  @(negedge bck) begin					//send sdata from buffer
	if (wclk==0) begin sdata<=data_buf[31-cbit]; end 	//LSYN send
	else if (wclk==1) begin sdata<=data_buf[15-cbit]; end	//RSYN send
	cbit<=cbit+1;
	if (cbit==15 && wclk==0) 
		begin cbit<=0; wclk<=1; end			//LSYN1 end
	else if (cbit==15 && wclk==1) 
		begin cbit<=0; wclk<=0; data_buf<=data; end 	//RSYN1 end, new buffer read
end
endmodule



module dac_decoder (
	input wire rst_n,
        input clk_inh,          	//256kHz INH clk input
        input [2:0] ch_id,    		//cd4051 sample/hold controls a/b/c
        input [15:0] dac,       	//parallel input from dac
	output reg [31:0] data,		//32 bit
	output reg dtr			//data ready flag
);
reg [15:0] ch0;				//LREV
reg [15:0] ch6;				//RSYN2
reg [15:0] ch2;				//LSYN2
reg [15:0] ch1;				//RREV
reg [15:0] ch7;				//RSYN1
reg [15:0] ch3;				//LSYN1
initial begin
	ch0<=0; ch1<=0; ch2<=0; ch3<=0; ch6<=0; ch7<=0; dtr<=0; data<=0;
end

always  @(negedge clk_inh,negedge rst_n) begin
	if(!rst_n) begin
		dtr<=0; data<=0;
	end 
	else begin
	case (ch_id)
		4 : begin dtr<=0; end 			// empty
		0 : begin dtr<=0; ch0<=dac; end 	// LREV
		6 : begin dtr<=0; ch6<=dac; end 	// RSYN2 
		2 : begin dtr<=0; ch2<=dac; end 	// LSYN2
		5 : begin dtr<=0; end 			// empty
		1 : begin dtr<=0; ch1<=dac; end 	// RREV
		7 : begin dtr<=0; ch7<=dac; end 	// RSYN
		3 : begin dtr<=1; ch3<=dac; data = {dac,ch7}; end // LSYN
	endcase
	end
end
endmodule
</pre>

The <a href="https://www.youtube.com/watch?v=VIkrG32c1l0">first video</a> of clean capture (sorry for low volume, it was at night) (clean stereo, no reverb).




<h3>Problems and pitfalls</h3>

It turned out, that the verilog firmware periodically won't work. Let me explain: the same perfect code, the same .fs can be flashed into TangNano9K many times, and in 99% cases the sound wont be clean. Even worse: DIT pcb with working "clean sound" firmware turned off, then after hours, when you turn it on - it have already broken sound. Also, i found that the frequency of DTR (the flag that signals about full frame cycle pass) is slightly faster than WCLK (smth about 32.00010kHz@DTR vs exact 32.00000kHz@WCLK). I tried to use a couple of async FIFO versions between dac_decoder and i2s_serializer modules, but with no luck.

As a fpga synthesizer, i used opensource Yosys/Apicula/NextPNR, because due to war sanctions, we here in Russia were cut off from many programs, including Gowin IDE free license program.

<p><strong>To be continued</strong></p>

// ******************************************************************
//
// Digital audio filter and mixer.
// BHG_audio_filter_mixer.sv
//
// Written by Brian Guralnick.
// https://github.com/BrianHGinc
//
// August 2022 
//
// Supports 6 channel input, 1 channel out.
//
//
//
//
// For public use.
// Please be fair and keep my credits if you use it in your designs.
//
// ******************************************************************

module BHG_audio_filter_mixer #(

parameter int IN_BITS         = 8,                   // Number of bits for all input channels, A,B,C,D,E,F.
parameter bit IN_REP   [0:5]  = '{0,0,0,0,0,0},      // Each channel input representation. 0=Unsigned binary, 1=signed binary.
parameter int OUT_BITS        = 12,                  // Output bits.  12 is plenty, but you can use 16.


//                                       Control Register Reset defaults.
//                          Address  =     0    1    2    3    4    5    6         7         8    9 
parameter logic [7:0] RST_REGS [0:9] = '{ 64,  64,  64,  64,  64,  64, 128,  8'b00000000 ,  25, 128 }
//                                      VolA,VolB,VolC,VolD,VolE,VolF,mvol, INV{xxFEDCBA},bass,treb 

)(
input                              rst           ,
input                              clk           ,
input                              clk_en        ,
input                        [3:0] c_addr        ,
input                              c_wr          ,
input                        [7:0] c_din         ,
output logic                 [7:0] c_dout = 8'd0 ,
input                [IN_BITS-1:0] s_in    [0:5] ,
output wire  signed [OUT_BITS-1:0] s_out
);

logic         [4:0] seq         = 0 ; // This register is used to sequence the actions after every 'clk_en' pulse.
logic signed [15:0] audio_out   = 0 ;
assign s_out                    = (OUT_BITS)'(audio_out<<<(OUT_BITS-14)) ;

// ******************************************************************
// ***** Generate the control registers cregs ******
// ******************************************************************
logic [7:0] cregs [0:9] = '{default:0};
always_ff @(posedge clk) if (rst) cregs  <= RST_REGS; else if (c_wr) cregs[c_addr] <= c_din ;          // Register register writes.
always_ff @(posedge clk)                                             c_dout        <= cregs[c_addr] ;  // Present read of current register address.
// ******************************************************************

// **********************************************************************************************************
// ***** Wire s_in to sound_in resolving input representation and bit depth offset gain, divided by 4  ******
// **********************************************************************************************************
logic signed [15:0] ps_in    [0:5] ;
logic signed [15:0] sound_in [0:5] ;
always_comb for (int i=0;i<6;i++) ps_in[i]    = (((s_in[i]^(!IN_REP[i]<<(IN_BITS-1))) << (OUT_BITS-IN_BITS))) ; // resolve representation & gain
always_comb for (int i=0;i<6;i++) sound_in[i] = ps_in[i] >>> 2 ;                                                // divide signed gain by 4.
// *********************************************************************************************

// **********************************************************************************************************
// ***** Generate signed volume controls and negative invert volume option ******
// **********************************************************************************************************
logic signed [8:0] volume [0:5] ;
always_comb for (int i=0;i<6;i++) volume[i] = {cregs[7][i], (cregs[7][i] ? (cregs[i]^8'd255) : cregs[i])} ;
// **********************************************************************************************************

// **********************************************************************************************************
// ***** Consolidated clocked multiplier ******
// **********************************************************************************************************
logic signed [15:0] m_audio_in   = 0;
logic signed  [8:0] m_audio_gain = 0;
logic signed [23:0] m_audio_out  = 0;
always_ff @(posedge clk) m_audio_out <= m_audio_in * m_audio_gain ;
// **********************************************************************************************************

// **********************************************************************************************************
// ***** Consolidated clocked accumulator ******
// **********************************************************************************************************
logic signed [15:0] a_audio_in   = 0;
logic signed [15:0] a_audio_out  = 0;
always_ff @(posedge clk) if (seq==0) a_audio_out<=0; else a_audio_out<=a_audio_out+a_audio_in ;
// **********************************************************************************************************

localparam logic signed [15:0] clip_pos       = 8191 ;
           logic signed [23:0] dc_offset      = 0 ;
           logic signed [15:0] hf_offset      = 0 ;
           logic signed [15:0] lf_offset_adj  = 0 ;
           logic signed [15:0] hf_offset_adj  = 0 ;

           logic               dcc            = 0 ;                    // DC-Clamp flag.
           wire         [7:0]  bass           =  cregs[8]            ; // Adjustable from 1 to 63.   1 = most bass, 63 = least bass. Do not use 0, it allows DC thru.
           wire         [7:0]  treb           =  8'd255^cregs[9]     ; // Adjustable from 0 to 255.  255=no filter, full treble bandwidth. 0=muffled.
           wire         [7:0]  vol            =  cregs[6]            ; // Adjustable final volume. 128=100% volume, 0=mute, 255=200% volume with simple limiter.
// **********************************************************************************************************
// DSP logic.
// **********************************************************************************************************
always_ff @(posedge clk) begin

        if (rst) begin
                dc_offset    <= 0 ;
                seq          <= 0 ;
                 end else
        if (clk_en) begin
                seq          <= 0 ;
                end
    else begin

        if (seq!=23) seq <=seq+1'b1; // increment the sequence stopping at 23

// ************************************************
// ***** Channel A-F multiply gain
// ************************************************
        if (seq>=0 && seq<=5) begin m_audio_in <= sound_in[seq] ; m_audio_gain <= volume[seq] ; end
        
// ************************************************
// ***** Channel A-F add/sum together.
// ************************************************
                                a_audio_in <= 0 ;                     // Default to 0 sound being added to the accumulator.
        if (seq>=2 && seq<=7)   a_audio_in <=(16)'(m_audio_out>>>8);  // Add together the 6 channel audio inputs with assigned volume gain.

// ***************************************************************************************************
// ***** DC-filter equivalent double DC-clamping diodes on the output shorting out the DC filter cap.
// ***************************************************************************************************
        else if (seq==9) begin                                  
                         if ((a_audio_out+(dc_offset>>>8))>  clip_pos ) begin dcc<=1;dc_offset <=  ( clip_pos-a_audio_out)<<<8;end // Apply the equivalent rapid high limiter diode-clamping circuit onto the output waveform.
                    else if ((a_audio_out+(dc_offset>>>8))<(-clip_pos)) begin dcc<=1;dc_offset <=  (-clip_pos-a_audio_out)<<<8;end // Apply the equivalent rapid low  limiter diode-clamping circuit onto the output waveform.

                    // Diode clamp not hit, so, calculate the offset to be used in a RC current discharge formula.
                    else begin dcc<=0;lf_offset_adj <= (16)'((a_audio_out+(dc_offset>>>8))>>>8);end

                    end
                    

// ************************************************
// ***** DC-filter RC-discharge.
// ************************************************
        else if (seq==10 && !dcc) begin m_audio_in    <= lf_offset_adj ; m_audio_gain <= bass;end
        else if (seq==12 && !dcc)       dc_offset     <= dc_offset - m_audio_out;
        else if (seq==13)               a_audio_in    <= (16)'(dc_offset>>>8) ;  // Apply the DC filter to the output waveform.


// ************************************************
// ***** Low pass RC-charge filter.
// ************************************************
        else if (seq==15)               hf_offset_adj <= hf_offset - a_audio_out ;
        else if (seq==16)         begin m_audio_in    <= hf_offset_adj           ; m_audio_gain <= treb;end
        else if (seq==18)               a_audio_in    <= (16)'(m_audio_out>>>8)  ;


// *******************************************************
// ***** Final volume control with output 'rail' limiter.
// *******************************************************
        else if (seq==20)  begin hf_offset  <= a_audio_out ; m_audio_in <= a_audio_out; m_audio_gain<=vol; end

        else if (seq==22)  begin
                                 if ((m_audio_out>>>7) >  clip_pos) audio_out <= (16)'((( clip_pos)>>>1) + (audio_out>>>1)) ;
                            else if ((m_audio_out>>>7) < -clip_pos) audio_out <= (16)'(((-clip_pos)>>>1) + (audio_out>>>1)) ;
                            else                                    audio_out <= (16)'((m_audio_out>>>8) + (audio_out>>>1)) ; // last avg filter.
                        end

    end

end
endmodule

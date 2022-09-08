 `define USE_STEREO      // ********** ENABLE this line to turn one stereo output
 `define USE_DUAL_PSG    // ********** ENABLE this line to use 2 x YM2149 PSGs. IE: 6 sound channels

// ********************************************************************************************************************************
// YM2149_PSG_system Programmable Sound Generator based on Jose Tejada's GitHub repository https://github.com/jotego/jt49.
//
// Enhancements by BrianHG   : https://github.com/BrianHGinc
//             and Nockieboy : https://github.com/nockieboy
// You can also find us here : https://www.eevblog.com/forum/fpga/
// Technical info/specs here : https://www.eevblog.com/forum/fpga/fpga-vga-controller-for-8-bit-computer/msg4366420/#msg4366420
//
// ***************************************************
// New included source code:
// ***************************************************
//
`include "BHG_FP_clk_divider.v"       // -> Precision floating point clock divider to generate any desired system clock down to the Hz.
`include "I2S_transmitter.sv"         // -> I2S digital audio transmitter for all Audio DACs/Codecs and HDMI transmitters.
`include "BHG_audio_filter_mixer.sv"  // -> Offers a programmable channel mixing levels, DC filter with clamp, and treble/bass/master volume controls.

`include "BHG_jt49.v"                 // -> An enhanced modified version of the original jt49.v offering higher # of bits for the sound output channels.
`include "BHG_jt49_exp.v"             // -> A replacement for the original jt49_exp.v using the tables in BHG_jt49_exp_lut.vh.

`include "jt49_hdl/jt49_cen.v"        // Legacy core HDL from Jose Tejada's GitHub repository https://github.com/jotego/jt49.
`include "jt49_hdl/jt49_div.v"  
`include "jt49_hdl/jt49_noise.v"
`include "jt49_hdl/jt49_eg.v"   
//
// 
// Enhancements include:
// ----------------------
// Stereo sound with control registers for channel mixing volume with phase inversion.  (Phase inversion allows for wide stage sound effect, or surround channels.)
// Registers for Treble, Bass and global volume adjustments.
// Smart DC filtering allowing lower frequency output while managing peaks and switch on/off pops when necessary.
// Improved precision 8 thru 14 bit exponential DAC support.  (10 bit almost exactly replicates the YM2149 normalized output voltage).
// Precision floating point system clock divider offering parameter select-able PSG reference frequencies with accuracy down to the Hz.
// Integrated standard I2S transmitter output with resampling & floating point system clock divider offering DAC Khz settings down to the Hz.
//
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************

module YM2149_PSG_system #(

    parameter      CLK_IN_HZ        = 100000000, // Input clock frequency
    parameter      CLK_I2S_IN_HZ    = 200000000, // Input clock frequency
    parameter      CLK_PSG_HZ       = 1789000,   // PSG clock frequency
    parameter      I2S_DAC_HZ       = 48000,     // I2S audio dac frequency
    parameter      YM2149_DAC_BITS  = 8,         // PSG DAC bit precision, 8 through 14 bits, the higher the bits, the higher the dynamic range.
                                                 // 10 bits almost perfectly replicates the YM2149 DA converter's Normalized voltage.
                                                 // With 8 bits, the lowest volumes settings will be slightly louder than normal.
                                                 // With 12 bits, the lowest volume settings will be too quiet.

    parameter      MIXER_DAC_BITS   = 16         // The number of DAC bits for the BHG_jt49_filter_mixer output.

)(

    input                                     clk,
    input                                     clk_i2s,
    input                                     reset_n,
    input                              [ 7:0] addr,      // register address
    input                              [ 7:0] data,      // data IN to PSG
    input                                     wr_n,      // data/addr valid

    output logic                       [ 7:0] dout = 8'd0, // PSG data output
    output wire                               i2s_sclk,    // I2S serial bit clock output
    output wire                               i2s_lrclk,   // I2S L/R output
    output wire                               i2s_data,    // I2S serial audio out
    output wire  signed  [MIXER_DAC_BITS-1:0] sound,       // parallel   audio out, mono or left channel
    output wire  signed  [MIXER_DAC_BITS-1:0] sound_right  // parallel   audio out, right channel

);

    // Signal declarations
    wire                              i2s_clk                   ; // I2S divided clock
    wire                              i2s_stb                   ; // I2S divided strobe
    wire                              p_div                     ; // PSG divided clock
    wire                              p_stb                     ; // PSG divided strobe
    wire                              sample_stb                ; // Strobe for when the sample is ready
    wire        [YM2149_DAC_BITS-1:0] sound_A, sound_B, sound_C ;
    wire        [YM2149_DAC_BITS+1:0] sound_mix                 ;
    wire signed  [MIXER_DAC_BITS-1:0] sound_left                ;

    // *******************************************************************************
    // Select which data to send out.
    // *******************************************************************************
    
    wire [7:0] rr_psg_a,rr_psg_b,rr_fmix_l,rr_fmix_r;

    // Select which read register to transmit back to the 'dout' port depending on the addr input.
        always_ff @(posedge clk)  dout <= (addr[7:4]==4'b1001) ? rr_fmix_r :
                                          (addr[7:4]==4'b1000) ? rr_fmix_l : 
                                          (addr[7:4]==4'b0001) ? rr_psg_b  :
                                          (addr[7:4]==4'b0000) ? rr_psg_a  : 8'd0 ;
    
    // *******************************************************************************
    // Instantiate fp_div for PSG
    // *******************************************************************************
    BHG_FP_clk_divider #(
   
        .INPUT_CLK_HZ  (CLK_IN_HZ ),  // Source clk_in frequency.
        .OUTPUT_CLK_HZ (CLK_PSG_HZ)   // Target synthesized output frequency.
   
    ) fdiv_psg (

        .clk_in        ( clk      ),  // System source clock.
        .rst_in        ( 1'b0     ),  // Synchronous reset.
        .clk_out       ( p_div    ),  // Synthesized output clock, 50:50 duty cycle.
        .clk_p0        ( p_stb    ),  // Strobe pulse at the rise of 'clk_out'.
        .clk_p180      (          )   // Strobe pulse at the fall of 'clk_out'.

    );

    // *******************************************************************************
    // Instantiate second fp_div for I2S transmitter
    // *******************************************************************************
    BHG_FP_clk_divider #(

        .INPUT_CLK_HZ  ( CLK_I2S_IN_HZ ),  // Source clk_in frequency.
        .OUTPUT_CLK_HZ ( I2S_DAC_HZ*64 )   // Target synthesized output frequency.

    ) fdiv_i2s (

        .clk_in        ( clk_i2s       ),  // System source clock.
        .rst_in        ( 1'b0          ),  // Synchronous reset.
        .clk_out       ( i2s_clk       ),  // Synthesized output clock, 50:50 duty cycle.
        .clk_p0        ( i2s_stb       ),  // Strobe pulse at the rise of 'clk_out'.
        .clk_p180      (               )   // Strobe pulse at the fall of 'clk_out'.

    );

    // *******************************************************************************
    // Instantiate PSGs
    // *******************************************************************************
    BHG_jt49 #(

        .DAC_BITS   ( YM2149_DAC_BITS   ) 

    ) PSG (

        .rst_n      ( reset_n                      ),
        .clk        ( clk                          ),
        .clk_en     ( p_stb                        ),
        .addr       ( addr[3:0]                    ),
        .cs_n       ( 1'b0                         ),
        .wr_n       ( wr_n || (addr[7:4]!=4'b0000) ),  // Set the primary PSG's address offset to 0.
        .din        ( data                         ),
        .sel        ( 1'b1                         ),
        .dout       ( rr_psg_a                     ),
        .sound      ( sound_mix                    ),
        .A          ( sound_A                      ),
        .B          ( sound_B                      ),
        .C          ( sound_C                      ),
        .sample     ( sample_stb                   ),
        .IOA_in     (                              ),
        .IOA_out    (                              ),
        .IOB_in     (                              ),
        .IOB_out    (                              )
        
    );

    // *******************************************************************************
    // Optional second PSG.
    // *******************************************************************************
`ifdef USE_DUAL_PSG

    wire [YM2149_DAC_BITS-1:0] sound_D, sound_E, sound_F ;

    BHG_jt49 #(

        .DAC_BITS   ( YM2149_DAC_BITS   ) 

    ) PSG_b (

        .rst_n      ( reset_n                      ),
        .clk        ( clk                          ),
        .clk_en     ( p_stb                        ),
        .addr       ( addr[3:0]                    ),
        .cs_n       ( 1'b0                         ),
        .wr_n       ( wr_n || (addr[7:4]!=4'b0001) ),  // Set the second PSG's address offset to +16.
        .din        ( data                         ),
        .sel        ( 1'b1                         ),
        .dout       ( rr_psg_b                     ),
        .sound      (                              ),
        .A          ( sound_D                      ),
        .B          ( sound_E                      ),
        .C          ( sound_F                      ),
        .sample     (                              ),
        .IOA_in     (                              ),
        .IOA_out    (                              ),
        .IOB_in     (                              ),
        .IOB_out    (                              )
        
    );

`else     // Default 'center' 0 the unused channels so the compiler will prune the unused logic.
    wire        [YM2149_DAC_BITS-1:0] sound_D=(1'b1<<(YM2149_DAC_BITS-1)), sound_E=(1'b1<<(YM2149_DAC_BITS-1)), sound_F=(1'b1<<(YM2149_DAC_BITS-1)) ; 
    assign      rr_psg_b = 8'b0 ;
`endif

    // *******************************************************************************
    // Instantiate PSG DC filter and audio filter
    // *******************************************************************************

    BHG_audio_filter_mixer #(

        .IN_BITS    ( YM2149_DAC_BITS   ),                                     // Number of bits for all input channels, A,B,C,D,E,F.
        .IN_REP     ( '{0,0,0,0,0,0}    ),                                     // Each channel input representation. 0=Unsigned binary, 1=signed binary.
        .OUT_BITS   ( MIXER_DAC_BITS    ),                                     // Output bits.  12 is plenty, but you can use 16.

         // Control Register Reset defaults.
         // Address =      0    1    2    3    4    5    6         7         8    9 
        .RST_REGS   ( '{  64,  64,  64,  64,  64,  64, 128,  8'b00000000 ,  25, 128 } )
                     // VolA,VolB,VolC,VolD,VolE,VolF,mvol, INV{xxFEDCBA},bass,treb 

    ) FMIX_LEFT (   // Use 2 modules for stereo out

        .rst        ( ~reset_n                                           ),
        .clk        ( clk                                                ),
        .clk_en     ( sample_stb                                         ),
        .c_addr     ( addr[3:0]                                          ),  // See source file for register map.
        .c_wr       ( ~(wr_n || (addr[7:4]!=4'b1000))                    ),  // Set the Left channel's FMIX MSB address offset to +128.
        .c_din      ( data                                               ),
        .c_dout     ( rr_fmix_l                                          ),
        .s_in       ( '{sound_A,sound_B,sound_C,sound_D,sound_E,sound_F} ),  // 6 input channels.
        .s_out      ( sound_left                                         )
        
    );

    // *******************************************************************************
    // Optional right channel for stereo.
    // *******************************************************************************

`ifdef USE_STEREO
    BHG_audio_filter_mixer #(

        .IN_BITS    ( YM2149_DAC_BITS   ),                                     // Number of bits for all input channels, A,B,C,D,E,F.
        .IN_REP     ( '{0,0,0,0,0,0}    ),                                     // Each channel input representation. 0=Unsigned binary, 1=signed binary.
        .OUT_BITS   ( MIXER_DAC_BITS    ),                                     // Output bits.  12 is plenty, but you can use 16.

         // Control Register Reset defaults.
         // Address =      0    1    2    3    4    5    6         7         8    9 
        .RST_REGS   ( '{  64,  64,  64,  64,  64,  64, 128,  8'b00000000 ,  25, 128 } )
                     // VolA,VolB,VolC,VolD,VolE,VolF,mvol, INV{xxFEDCBA},bass,treb 

    ) FMIX_RIGHT (   // Right channel

        .rst        ( ~reset_n                                           ),
        .clk        ( clk                                                ),
        .clk_en     ( sample_stb                                         ),
        .c_addr     ( addr[3:0]                                          ),  // See source file for register map.
        .c_wr       ( ~(wr_n || (addr[7:4]!=4'b1001))                    ),  // Set the Right channel's FMIX MSB address offset to +144.
        .c_din      ( data                                               ),
        .c_dout     ( rr_fmix_r                                          ),
        .s_in       ( '{sound_A,sound_B,sound_C,sound_D,sound_E,sound_F} ),  // 6 input channels.
        .s_out      ( sound_right                                        )

    );

    assign   sound       = sound_left  ;

`else
    assign   sound_right = sound_left ; // remove this line when enabling stereo.
    assign   sound       = sound_left ;
    assign   rr_fmix_r   = 8'd0 ;
`endif

    // *******************************************************************************
    // Instantiate I2S transmitter for HDMI / DAC
    // *******************************************************************************

    // Metastable clock domain crossing.
    // This code works because the clk and clk_i2s domains have many multiple cycles between the time a new
    // value is assigned to very slow sound_left / sound_right audio channels.

    logic sample_toggle = 0 ;
    always_ff @(posedge clk) if (sample_stb) sample_toggle <= !sample_toggle; // Render a toggle register once every new sample.

    logic [3:0] st_shift = 0;
    always_ff @(posedge clk_i2s) st_shift   <= {st_shift[2:0],sample_toggle}; // Roll in the sample toggle into the I2S clock domain.
    wire                         take_sample = st_shift[3] ^ st_shift[2] ; // Create a wire which sees the toggle in the I2S clock domain.

    logic   [MIXER_DAC_BITS-1:0] so_l = 0, so_r = 0 ;
    always_ff @(posedge clk_i2s) if (take_sample)  {so_l,so_r} <= {sound_left,sound_right}; // transfer sample data to a register in the I2S clock domain.

    I2S_transmitter #(

        .BITS           ( MIXER_DAC_BITS    ),
        .INV_BCLK       (                 0 )

    ) I2S_TX (

        .clk_in         ( clk_i2s     ), // High speed clock
        .clk_i2s        ( i2s_clk     ), // 50/50 duty cycle serial audio clock
        .clk_i2s_pulse  ( i2s_stb     ), // Strobe for 1 clk_in cycle at the beginning of each clk_i2s
        .sample_in      ( 1'b0        ), // Optional input to reset the sample position.  This should either be tied to GND or only pulse once every 64 'clk_i2s_pulse's
        .DAC_Left       ( so_l        ), // Left channel digital audio sampled once every 'sample_pulse' output
        .DAC_Right      ( so_r        ), // Right channel digital audio sampled once every 'sample_pulse' output

        .sample_pulse   (             ), // Pulses once when a new stereo sample is taken from the DAC_Left/Right inputs.
        .I2S_BCLK       ( i2s_sclk    ), // I2S serial bit clock output (SCLK), basically the clk_i2s input in the correct phase
        .I2S_WCLK       ( i2s_lrclk   ), // I2S !left / right output (LRCLK)
        .I2S_DATA       ( i2s_data    )  // Serial data output    

    );

endmodule

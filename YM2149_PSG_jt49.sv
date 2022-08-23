// **********************************************************************************************************************************
//
// YM2149_PSG_system backward compliant implementation of:
//
//                     Legacy core HDL from Jose Tejada's GitHub repository https://github.com/jotego/jt49.
//
// **********************************************************************************************************************************

`include "BHG_FP_clk_divider.v"       // -> Precision floating point clock divider to generate any desired system clock down to the Hz.
`include "I2S_transmitter.sv"         // -> I2S digital audio transmitter for all Audio DACs/Codecs and HDMI transmitters.
`include "jt49_hdl/jt49.v"
`include "jt49_hdl/jt49_exp.v"
`include "jt49_hdl/jt49_cen.v"
`include "jt49_hdl/jt49_div.v"
`include "jt49_hdl/jt49_noise.v"
`include "jt49_hdl/jt49_eg.v"
`include "jt49_hdl/filter/jt49_dcrm2.v"
`include "jt49_hdl/filter/jt49_mave.v"
`include "jt49_hdl/filter/jt49_dly.v"


module YM2149_PSG_system #(

    parameter      CLK_IN_HZ        = 100000000, // Input clock frequency
    parameter      CLK_I2S_IN_HZ    = 200000000, // Input clock frequency
    parameter      CLK_PSG_HZ       = 1789000,   // PSG clock frequency
    parameter      I2S_DAC_HZ       = 48000,     // I2S audio dac word frequency

    parameter      YM2149_DAC_BITS  = 8,         // *********************************  N/A ******************************
    parameter      MIXER_DAC_BITS   = 10,        // *********************************  N/A ******************************

    parameter      LPFILTER_DEPTH   = 4          // 2=flat to 10khz, 4=flat to 5khz, 6=getting muffled, 8=no treble.

)(

    input                                     clk,
    input                                     clk_i2s,
    input                                     reset_n,
    input                              [ 7:0] addr,      // register address
    input                              [ 7:0] data,      // data IN to PSG
    input                                     wr_n,      // data/addr valid

    output wire                        [ 7:0] dout,      // PSG data output
    output wire                               i2s_sclk,  // I2S serial bit clock output
    output wire                               i2s_lrclk, // I2S L/R output
    output wire                               i2s_data,  // I2S serial audio out
    output wire  signed [YM2149_DAC_BITS+1:0] sound,          // parallel   audio out
    output wire  signed [YM2149_DAC_BITS+1:0] sound_right // dummy output for simulation testbench.

);

    assign sound_right = 0 ;

    // Signal declarations
    wire                              i2s_clk     ; // I2S divided clock
    wire                              i2s_stb     ; // I2S divided strobe
    wire                              p_div       ; // PSG divided clock
    wire                              p_stb       ; // PSG divided strobe
    wire                              sample_stb  ; // Strobe for when the sample is ready
    wire        [YM2149_DAC_BITS-1:0] sound_A, sound_B, sound_C ;
    wire        [YM2149_DAC_BITS+1:0] sound_mix   ;
    wire signed [YM2149_DAC_BITS+1:0] sound_dcf   ;

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
        .clk_p180      (          )); // Strobe pulse at the fall of 'clk_out'.


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
        .clk_p180      (               )); // Strobe pulse at the fall of 'clk_out'.


    // *******************************************************************************
    // Instantiate PSG
    // *******************************************************************************
    jt49 #(

        .COMP       ( 2'b00 )

    ) PSG (

        .rst_n      ( reset_n                      ),
        .clk        ( clk                          ),
        .clk_en     ( p_stb                        ),
        .addr       ( addr[3:0]                    ),
        .cs_n       ( 1'b0                         ),
        .wr_n       ( wr_n || (addr[7:4]!=4'b0000) ),  // Select for the PSG's MSB address in case we want multiple PSGs.
        .din        ( data                         ),
        .sel        ( 1'b1                         ),
        .dout       ( dout                         ),
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
    // Instantiate PSG DC filter and audio filter
    // *******************************************************************************

    jt49_mave #(

        .dw    ( YM2149_DAC_BITS+2 ),
        .depth ( LPFILTER_DEPTH    )

    ) PSG_LPF (

        .clk   ( clk            ),
        .cen   ( sample_stb     ),
        .rst   ( ~reset_n       ),
        .din   ( sound_mix      ),
        .dout  ( sound_dcf      )
        
    );

    jt49_dcrm2 #(

        .sw    ( YM2149_DAC_BITS+2 )

    ) PSG_DCFILT (

        .clk   ( clk        ),
        .cen   ( sample_stb ),
        .rst   ( ~reset_n   ),
        .din   ( sound_dcf  ),
        .dout  ( sound      )

    );


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

logic   [MIXER_DAC_BITS-1:0] so = 0 ;
always_ff @(posedge clk_i2s) if (take_sample)  so <= sound ; // transfer sample data to a register in the I2S clock domain.


    I2S_transmitter #(

        .BITS           ( MIXER_DAC_BITS    ),
        .INV_BCLK       (                 0 )

    ) I2S_TX (

        .clk_in         ( clk_i2s     ), // High speed clock
        .clk_i2s        ( i2s_clk     ), // 50/50 duty cycle serial audio clock
        .clk_i2s_pulse  ( i2s_stb     ), // Strobe for 1 clk_in cycle at the beginning of each clk_i2s
        .sample_in      ( 1'b0        ), // Optional input to reset the sample position.  This should either be tied to GND or only pulse once every 64 'clk_i2s_pulse's
        .DAC_Left       ( so          ), // Left channel digital audio sampled once every 'sample_pulse' output
        .DAC_Right      ( so          ), // Right channel digital audio sampled once every 'sample_pulse' output

        .sample_pulse   (             ), // Pulses once when a new stereo sample is taken from the DAC_Left/Right inputs.
        .I2S_BCLK       ( i2s_sclk    ), // I2S serial bit clock output (SCLK), basically the clk_i2s input in the correct phase
        .I2S_WCLK       ( i2s_lrclk   ), // I2S !left / right output (LRCLK)
        .I2S_DATA       ( i2s_data    )  // Serial data output    

    );

endmodule

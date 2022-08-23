`timescale 1 ps/1 ps

// ********************************************************************************************************************************
// YM2149_PSG_system Programmable Sound Generator based on Jose Tejada's GitHub repository https://github.com/jotego/jt49.
//
// Enhancements by BrianHG    : https://github.com/BrianHGinc
//             and Nockieboy  : https://github.com/nockieboy
// You can also find use here : https://www.eevblog.com/forum/fpga/
//
//
// ***************************************************
// New included source code:
// ***************************************************
//
// YM2149_PSG_system_tb.sv     -> This test bench.
//
//   YM2149_PSG_system.sv      -> Wired up complete YM2149_PSG_system enhanced PSG system.
//   YM2149_PSG_jt49.sv        -> backward compliant implementation of Legacy core HDL from Jose Tejada's GitHub repository https://github.com/jotego/jt49.
//
// New sub-modules:
//   BHG_FP_clk_divider.v      -> Precision floating point clock divider to generate any desired system clock down to the Hz.
//   I2S_transmitter.sv        -> I2S digital audio transmitter for all Audio DACs/Codecs and HDMI transmitters.
//   BHG_jt49.v                -> An enhanced modified version of the original jt49.v offering higher # of bits for the sound output channels.
//   BHG_jt49_exp_tablegen.v   -> A generator the precision volumetric tables.  Generates the BHG_jt49_exp_lut.vh file.
//   BHG_jt49_exp_lut.vh       -> The parameter table generated after Sim running the BHG_jt49_exp_tablegen.v.
//   BHG_jt49_exp.v            -> A replacement for the original jt49_exp.v using the tables in BHG_jt49_exp_lut.vh.
//   BHG_audio_filter_mixer.sv -> Offers a programmable channel mixing levels, DC filter with clamp, and treble/bass/master volume controls.
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
// Functional simulation setup for Modelsim, with example YM2149 presets and full outputs with analog waveforms.
//
// *** Simulation also includes a switch to run Jose Tejada's original jt49 project for direct comparison.
//
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// Enable this 'define use_legacy_jt49' to simulate using Jose Tejada's original jt49 hdl:
//
//`define use_legacy_jt49         // Simulate original jt49 hdl.
`define use_YM2149_PSG_system   // Simulate new PSG_System.
//
// This will simulate the original jt49 YM2149 PSG source code
// from Jose Tejada's GitHub repository https://github.com/jotego/jt49
// *** Remember, when using, parameter YM2149_DAC_BITS must be set to 8!
//
// Patched files: 'jt49_dly.v', found a few bugs, see lines: 
// 29, 30, 31, & 39.
//
// Also found clip-inversion overflow bug in jt49_mave.v & jt49_dcrm2.v, which the
// DC filter seems to sometimes patch.  Though this may be looked at by Jose Tejada's,
// it is no longer in use because of the new 'BHG_jt49_filter_mixer.sv' replacement.
//
// To easily see this, when simulating, set integer 'PSG_PROG_NUM' to 4 or 5 at line 122
//
// ********************************************************************************************************************************
// ***************************************************
// How to run Modelsim simulation:
// ***************************************************
//
// Run Modelsim all on it's own.  (It comes with Intel Quartus 20.1 and earlier,
//                                 Lattice Diamond 3.12 and above, and other FPGA dev platforms.)
//
// Go into menu 'File / Change Directory' and choose this project's top folder.
//
// In the transcript window, type 'do setup_psg.do' to setup and run the simulation.
//
// Every time you make a source file change, to re-sim, just type 'do run_psg.do'
// in the transcript window to do a quick recompile and re-simulate.
//
//
// To render the volume control's DAC lookup tables, in the transcript type: 'do generate_lut.do'.
// The source file 'BHG_jt49_exp_tablegen.v' will then generate a new 'BHG_jt49_exp_lut.vh' file with
// LUT tables for 8 through 14 bit dacs, adjusted to it's localparam LSB_DB_CORRECTION setting.
//
// To show in Modelsim the new DAC normalized voltage waveform, set your desired .YM2149_DAC_BITS parameter
// at line #308 in this test-bench's HDL and in Modelsim's transcript, type 'do setup_dac.do'.
//
//
//
// *********************************************************************************************************************************
`ifdef use_legacy_jt49
`include "YM2149_PSG_jt49.sv"   // This will simulate the original jt49 YM2149 PSG source code
`else
`include "YM2149_PSG_system.sv" // This will simulate the new BrianHG & Nockieboy YM2149_PSG_system.
`endif
// ********************************************************************************************************************************
module YM2149_PSG_system_tb ();
// ********************************************************************************************************************************
// *** Set the test-bench environment parameters.     **********************************************************************
// ********************************************************************************************************************************

localparam bit QUICK_SIM = 1                                          ; // When running large simulations, turning this on will
                                                                        // shorten the time it takes to simulate at the expense of using
                                                                        // a slow CLK input.

localparam  CLK_PSG_HZ   = 1789000                                    ; // PSG clock frequency.
localparam  I2S_DAC_HZ   = 48000                                      ; // I2S audio dac frequency.  CD audio=44100, HDMI/DVI audio=48000.
localparam  CLK_IN_HZ    = QUICK_SIM ? (I2S_DAC_HZ*128)*1 : 100000000 ; // Select operating frequency of simulation.  (I2S_DAC_HZ*128) is
                                                                        // the minimum allowed frequency, otherwise use perfect multiples
                                                                        // of (I2S_DAC_HZ*128) or anything >50MHz offers good performance.

localparam  [63:0] RUNTIME_MS   = 200                                 ; // Number of milliseconds to simulate.  (Must be 64 bit because of picosecond time calculation)
localparam  [63:0] PS_NUMERATOR = 1000000 * 1000000                   ; // Need this number to be a 64bit integer.
localparam         CLK_PERIOD   = PS_NUMERATOR/CLK_IN_HZ              ; // Period of simulated clock.

// ********************************************************************************************************************************

// ********************************************************************************************************************************
// *** Set the new PSG_system environment parameters.     **********************************************************************
// ********************************************************************************************************************************
localparam         YM2149_DAC_BITS  = 8   ;  // PSG DAC bit precision, 8 through 12 bits, the higher the bits, the higher the dynamic range.
                                             // 10 bits almost perfectly replicates the YM2149 DA converter's Normalized voltage.
                                             // With 8 bits, the lowest volumes settings will be slightly louder than normal.
                                             // With 12 bits, the lowest volume settings will be too quiet.
localparam         MIXER_DAC_BITS   = 16  ;  // The number of DAC bits for the BHG_jt49_filter_mixer core and output.

localparam         LPFILTER_DEPTH   = 4   ;  // Legacy control for original jt49 HDL.  2=flat to 10khz, 4=flat to 5khz, 6=getting muffled, 8=no treble.

// ********************************************************************************************************************************
// *** Initialize the YM2149 with these programs to generate sample audio.  *******************************************************
// *** Set integer PSG_PROG_NUM to choose which YM2149 presets to use.      *******************************************************
// ********************************************************************************************************************************
//
    localparam        CMD_COUNT               = 21                       ; // Number of commands to send to PSG.
    localparam        MAX_SEQ                 = 9                        ; // Number of PSG test settings.
    localparam        PSG_PC                  = 10                       ; // Number of PSG sequences to send.
    integer           PSG_PROG_NUM [1:PSG_PC] = '{2,1,7,6,8,6,6,5,5,5}   ; // Select which PSG_PROG_NUMs to run in the PSG.
    localparam [63:0] PSG_NPORG_DELAY         = 100                      ; // number of ms between PSG programs.

    reg [ 7:0] addr [1:MAX_SEQ][1:CMD_COUNT]  = '{default:0} ;
    reg [ 7:0] data [1:MAX_SEQ][1:CMD_COUNT]  = '{default:0} ;

initial begin
// **************************************************************************************************************************************
// PSG_PROG_NUM 1: Show the DAC exponential LUT table by
// modulating volume ramp of a 10Khz square wave on channel A.
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [1]   = '{  0,  1,  2,  3,  4,  5,  6,       7    ,  8,  9, 10, 11, 12, 13,        128,129,130,134,    135    ,136,137 } ;
    data [1]   = '{ 44,  0,  1,  0,  1,  0,  1, 8'b00111110, 16,  0,  0, 75,  0, 14,         64, 64, 64,128,8'b00000000, 25,  8 } ;
// **************************************************************************************************************************************
// PSG_PROG_NUM 2: Test the audio filter performance with all 3 channels at maximum gain
// running at different frequencies.
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [2]   = '{  0,  1,  2,  3,  4,  5,  6,       7    ,  8,  9, 10, 11, 12, 13,        128,129,130,134,    135    ,136,137 } ;
    data [2]   = '{ 94,  4, 11,  0,  0,  3,  5, 8'b00111000, 15, 15, 15,125,  0, 14,         64, 64, 64,128,8'b00000000, 25,128 } ;
// **************************************************************************************************************************************
// PSG_PROG_NUM 3: Test the audio filter performance with all 3 channels at maximum gain
// running a 27 hz wave.  (Good for testing the DC filter's performance)
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [3]   = '{  0,  1,  2,  3,  4,  5,  6,       7    ,  8,  9, 10, 11, 12, 13,        128,129,130,134,    135    ,136,137 } ;
    data [3]   = '{255, 15,255, 15,255, 15,  5, 8'b00111000, 15, 15, 15,125,  0, 14,         64, 64, 64,128,8'b00000000, 25,128 } ;
// **************************************************************************************************************************************
// PSG_PROG_NUM 4: Test the audio filter performance with all 3 channels at maximum gain
// running a 5 Khz wave.  (Good for testing the LPF filter's performance)
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [4]   = '{  0,  1,  2,  3,  4,  5,  6,       7    ,  8,  9, 10, 11, 12, 13,        128,129,130,134,    135    ,136,137 } ;
    data [4]   = '{ 22,  0, 22,  0, 22,  0,  5, 8'b00111000, 15, 15, 15,125,  0, 14,         64, 64, 64,128,8'b00000000, 25,128 } ;
// **************************************************************************************************************************************
// PSG_PROG_NUM 5: Test the audio filter performance with all 3 channels at maximum gain
// running a 5 Khz wave mixed with a 27Hz wave.  (Good for testing the complete filter's  performance)
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [5]   = '{  0,  1,  2,  3,  4,  5,  6,       7    ,  8,  9, 10, 11, 12, 13,        128,129,130,134,    135    ,136,137 } ;
    data [5]   = '{ 22,  0,255, 15,255, 15,  5, 8'b00111000, 15, 15, 15,125,  0, 14,         64, 64, 64,128,8'b00000000, 25,  8 } ;
// ***************************************************************************************************************************************
// **************************************************************************************************************************************
// PSG_PROG_NUM 6: Test the audio filter performance with all 3 channels at mute
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [6]   = '{  0,  1,  2,  3,  4,  5,  6,       7    ,  8,  9, 10, 11, 12, 13,        128,129,130,134,    135    ,136,137 } ;
    data [6]   = '{255, 15,255, 15,255, 15,  5, 8'b00111000,  0,  0,  0,125,  0, 14,         64, 64, 64,128,8'b00000000, 25,  8 } ;
// **************************************************************************************************************************************
// PSG_PROG_NUM 7: *PSG_B Test the audio filter performance with all 3 channels at maximum gain
// running at different frequencies.
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [7]   = '{ 16, 17, 18, 19, 20, 21, 22,      23    , 24, 25, 26, 27, 28, 29,        128,129,130,134,    135    ,136,137 } ;
    data [7]   = '{ 94,  4, 11,  0,  0,  3,  5, 8'b00111000, 15, 15, 15,125,  0, 14,         64, 64, 64,128,8'b00000000, 25,  8 } ;
// ***************************************************************************************************************************************
// **************************************************************************************************************************************
// PSG_PROG_NUM 8: *PSG_B Test the audio filter performance with all 3 channels at mute
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [8]   = '{ 16, 17, 18, 19, 20, 21, 22,      23    , 24, 25, 26, 27, 28, 29,        128,129,130,134,    135    ,136,137 } ;
    data [8]   = '{ 94,  4, 11,  0,  0,  3,  5, 8'b00111000,  0,  0,  0,125,  0, 14,         64, 64, 64,128,8'b00000000, 25,  8 } ;
// **************************************************************************************************************************************
// PSG_PROG_NUM 9: 8 & 9, pop test.
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [9]   = '{ 16, 17, 18, 19, 20, 21, 22,      23    , 24, 25, 26, 27, 28, 29,        128,129,130,134,    135    ,136,137 } ;
    data [9]   = '{ 94,  4, 11,  0,  0,  3,  5, 8'b00111000,  0,  0,  0,125,  0, 14,         64, 64, 64,128,8'b00000001, 25,  8 } ;
// **************************************************************************************************************************************
end

    // PSG command sequencer
    integer    step = 0   ; // instruction step position.
    integer    z    = 0   ; // Which PSG_PROG_NUM to send.
    // Signal declarations
    reg        clk  = 0, reset = 0, wr_n = 1 ;


// `define USE_STEREO      // ********** ENABLE this line to turn one stereo output
// `define USE_DUAL_PSG    // ********** ENABLE this line to use dual YM2149 PSGs. IE: 6 sound channels

YM2149_PSG_system #(

   .CLK_IN_HZ       ( CLK_IN_HZ       ), // Calculated input clock frequency
   .CLK_I2S_IN_HZ   ( CLK_IN_HZ       ), // Calculated input clock frequency
   .CLK_PSG_HZ      ( CLK_PSG_HZ      ), // Desired PSG clock frequency (Hz)
   .I2S_DAC_HZ      ( I2S_DAC_HZ      ), // Desired I2S audio dac word clock (Hz)

//-------------------------------------------------------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------------------------------------------------------
// *** This 'ifdef' is only for simulating the legacy jt49 mode.
`ifdef use_legacy_jt49 
   .YM2149_DAC_BITS ( 8               ),   // Force 8 bit for legacy mode.
   .LPFILTER_DEPTH  ( LPFILTER_DEPTH  ),   // Legacy control for original jt49 HDL.  2=flat to 10khz, 4=flat to 5khz, 6=getting muffled, 8=no treble.
`else
//-------------------------------------------------------------------------------------------------------------------------------------------------
   .YM2149_DAC_BITS ( YM2149_DAC_BITS ),   // PSG DAC bit precision, 8 through 14 bits, the higher the bits, the higher the dynamic range.
                                           // 10 bits almost perfectly replicates the YM2149 DA converter's Normalized voltage.
                                           // With 8 bits, the lowest volumes settings will be slightly louder than normal.
                                           // With 12 bits, the lowest volume settings will be too quiet.
`endif
//-------------------------------------------------------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------------------------------------------------------

   .MIXER_DAC_BITS  ( MIXER_DAC_BITS  )    // The number of DAC bits for the BHG_jt49_filter_mixer core and output.

) PSG (

   .clk            (                         clk ),
   .clk_i2s        (                         clk ),
   .reset_n        (                       reset ),
   .addr           ( addr[PSG_PROG_NUM[z]][step] ), // register address
   .data           ( data[PSG_PROG_NUM[z]][step] ), // data IN to PSG
   .wr_n           (                        wr_n ), // data/addr valid

   .dout           (            ), // PSG data output
   .i2s_sclk       (            ), // I2S serial bit clock output
   .i2s_lrclk      (            ), // I2S L/R output
   .i2s_data       (            ), // I2S serial audio out
   .sound          (            ), /// parallel  audio out, mono or left channel
   .sound_right    (            )  /// parallel  audio out, right channel

);

    initial begin
// ***********************************************************************************************************************************************
        #(CLK_PERIOD*2);reset=1'b1;#(CLK_PERIOD*2)  // Wait for 2 system clks before and after reset.
// ***********************************************************************************************************************************************
//      Count out the command counter until the end, waiting a system clock between each command step + an extra wait for the last command at the end.
    for (z=1;z<=PSG_PC;z++) begin
        for (step=1; step<=CMD_COUNT; step++ ) begin wr_n=1'b0;#(CLK_PERIOD);wr_n=1'b1;#(CLK_PERIOD);end
        #(PSG_NPORG_DELAY * 1000 * 1000 * 1000);
    end
// ***********************************************************************************************************************************************
    end

// ***********************************************************************************************************************************************
    always begin clk=1'b1;#(CLK_PERIOD/2);clk=1'b0;#(CLK_PERIOD/2);end // an ipso-de-facto source clock generator.
// ***********************************************************************************************************************************************
    always #(RUNTIME_MS * 1000 * 1000 * 1000) $stop ;                  // Stop simulation at RUNTIME_MS (milliseconds).
// ***********************************************************************************************************************************************

endmodule

// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ***                                                                                                                        *****
// ***                                                                                                                        *****
// ***     Render nothing but the DAC ramp                                                                                    *****
// ***                                                                                                                        *****
// ***                                                                                                                        *****
// ***                                                                                                                        *****
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************
// ********************************************************************************************************************************

module YM2149_Render_DAC_tb ();
// ********************************************************************************************************************************
// *** Set the test-bench environment parameters.     **********************************************************************
// ********************************************************************************************************************************

localparam bit QUICK_SIM = 1                                          ; // When running large simulations, turning this on will
                                                                        // shorten the time it takes to simulate at the expense of using
                                                                        // a slow CLK input.

localparam  CLK_PSG_HZ   = 1789000                                    ; // PSG clock frequency.
localparam  I2S_DAC_HZ   = 48000                                      ; // I2S audio dac frequency.  CD audio=44100, HDMI/DVI audio=48000.
localparam  CLK_IN_HZ    = QUICK_SIM ? (I2S_DAC_HZ*128)*1 : 100000000 ; // Select operating frequency of simulation.  (I2S_DAC_HZ*128) is
                                                                        // the minimum allowed frequency, otherwise use perfect multiples
                                                                        // of (I2S_DAC_HZ*128) or anything >50MHz offers good performance.

localparam  [63:0] RUNTIME_MS   = 41                                  ; // Number of milliseconds to simulate.  (Must be 64 bit because of picosecond time calculation)
localparam  [63:0] PS_NUMERATOR = 1000000 * 1000000                   ; // Need this number to be a 64bit integer.
localparam         CLK_PERIOD   = PS_NUMERATOR/CLK_IN_HZ              ; // Period of simulated clock.

// ********************************************************************************************************************************

// ********************************************************************************************************************************
// *** Set the new PSG_system environment parameters.     **********************************************************************
// ********************************************************************************************************************************
localparam         YM2149_DAC_BITS  = 10  ;  // PSG DAC bit precision, 8 through 12 bits, the higher the bits, the higher the dynamic range.
                                             // 10 bits almost perfectly replicates the YM2149 DA converter's Normalized voltage.
                                             // With 8 bits, the lowest volumes settings will be slightly louder than normal.
                                             // With 12 bits, the lowest volume settings will be too quiet.
localparam         MIXER_DAC_BITS   = 16  ;  // The number of DAC bits for the BHG_jt49_filter_mixer core and output.

localparam         LPFILTER_DEPTH   = 4   ;  // Legacy control for original jt49 HDL.  2=flat to 10khz, 4=flat to 5khz, 6=getting muffled, 8=no treble.

// ********************************************************************************************************************************
// *** Initialize the YM2149 with these programs to generate sample audio.  *******************************************************
// *** Set integer PSG_PROG_NUM to choose which YM2149 presets to use.      *******************************************************
// ********************************************************************************************************************************
//
    localparam        CMD_COUNT               = 14                       ; // Number of commands to send to PSG.
    localparam        MAX_SEQ                 = 8                        ; // Number of PSG test settings.
    localparam        PSG_PC                  = 1                        ; // Number of PSG sequences to send.
    integer           PSG_PROG_NUM [1:PSG_PC] = '{1}                     ; // Select which PSG_PROG_NUMs to run in the PSG.
    localparam [63:0] PSG_NPORG_DELAY         = 100                      ; // number of ms between PSG programs.

    reg [ 7:0] addr [1:MAX_SEQ][1:CMD_COUNT]  = '{default:0} ;
    reg [ 7:0] data [1:MAX_SEQ][1:CMD_COUNT]  = '{default:0} ;

initial begin
// **************************************************************************************************************************************
// PSG_PROG_NUM 1: Show the DAC exponential LUT table by
// modulating volume ramp of a 10Khz square wave on channel A.
// **************************************************************************************** BHG_jt49_filter_mixer controls **************
    addr [1]   = '{  0,  1,  2,  3,  4,  5,  6,       7    ,  8,  9, 10, 11, 12, 13 } ;
    data [1]   = '{ 44,  0,  1,  0,  1,  0,  1, 8'b00111111, 16,  0,  0, 75,  0, 14 } ;
end

    // PSG command sequencer
    integer    step = 0   ; // instruction step position.
    integer    z    = 0   ; // Which PSG_PROG_NUM to send.
    // Signal declarations
    reg        clk  = 0, reset = 0, wr_n = 1 ;


// `define USE_STEREO      // ********** ENABLE this line to turn one stereo output
// `define USE_DUAL_PSG    // ********** ENABLE this line to use dual YM2149 PSGs. IE: 6 sound channels

YM2149_PSG_system #(

   .CLK_IN_HZ       ( CLK_IN_HZ       ), // Calculated input clock frequency
   .CLK_I2S_IN_HZ   ( CLK_IN_HZ       ), // Calculated input clock frequency
   .CLK_PSG_HZ      ( CLK_PSG_HZ      ), // Desired PSG clock frequency (Hz)
   .I2S_DAC_HZ      ( I2S_DAC_HZ      ), // Desired I2S audio dac word clock (Hz)

//-------------------------------------------------------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------------------------------------------------------
// *** This 'ifdef' is only for simulating the legacy jt49 mode.
`ifdef use_legacy_jt49 
   .YM2149_DAC_BITS ( 8               ),   // Force 8 bit for legacy mode.
   .LPFILTER_DEPTH  ( LPFILTER_DEPTH  ),   // Legacy control for original jt49 HDL.  2=flat to 10khz, 4=flat to 5khz, 6=getting muffled, 8=no treble.
`else
//-------------------------------------------------------------------------------------------------------------------------------------------------
   .YM2149_DAC_BITS ( YM2149_DAC_BITS ),   // PSG DAC bit precision, 8 through 14 bits, the higher the bits, the higher the dynamic range.
                                           // 10 bits almost perfectly replicates the YM2149 DA converter's Normalized voltage.
                                           // With 8 bits, the lowest volumes settings will be slightly louder than normal.
                                           // With 12 bits, the lowest volume settings will be too quiet.
`endif
//-------------------------------------------------------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------------------------------------------------------

   .MIXER_DAC_BITS  ( MIXER_DAC_BITS  )    // The number of DAC bits for the BHG_jt49_filter_mixer core and output.

) PSG (

   .clk            (                         clk ),
   .clk_i2s        (                         clk ),
   .reset_n        (                       reset ),
   .addr           ( addr[PSG_PROG_NUM[z]][step] ), // register address
   .data           ( data[PSG_PROG_NUM[z]][step] ), // data IN to PSG
   .wr_n           (                        wr_n ), // data/addr valid

   .dout           (            ), // PSG data output
   .i2s_sclk       (            ), // I2S serial bit clock output
   .i2s_lrclk      (            ), // I2S L/R output
   .i2s_data       (            ), // I2S serial audio out
   .sound          (            ), /// parallel  audio out, mono or left channel
   .sound_right    (            )  /// parallel  audio out, right channel

);

    initial begin
// ***********************************************************************************************************************************************
        #(CLK_PERIOD*2);reset=1'b1;#(CLK_PERIOD*2)  // Wait for 2 system clks before and after reset.
// ***********************************************************************************************************************************************
//      Count out the command counter until the end, waiting a system clock between each command step + an extra wait for the last command at the end.
    for (z=1;z<=PSG_PC;z++) begin
        for (step=1; step<=CMD_COUNT; step++ ) begin wr_n=1'b0;#(CLK_PERIOD);wr_n=1'b1;#(CLK_PERIOD);end
        #(PSG_NPORG_DELAY * 1000 * 1000 * 1000);
    end
// ***********************************************************************************************************************************************
    end

// ***********************************************************************************************************************************************
    always begin clk=1'b1;#(CLK_PERIOD/2);clk=1'b0;#(CLK_PERIOD/2);end // an ipso-de-facto source clock generator.
// ***********************************************************************************************************************************************
    always #(RUNTIME_MS * 1000 * 1000 * 1000) $stop ;                  // Stop simulation at RUNTIME_MS (milliseconds).
// ***********************************************************************************************************************************************


endmodule

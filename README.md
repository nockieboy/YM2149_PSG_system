# YM2149_PSG_system

## Programmable Sound Generator based on [Jose Tejada's GitHub repository](https://github.com/jotego/jt49)

This SystemVerilog project was born from the 8-bit FPGA GPU project [here](https://www.eevblog.com/forum/fpga/), as a nice-to-have addition to
the existing HDMI/DVI-compatible video display project designed to work with an 8-bit host computer (specifically, a unique DIY computer designed
and built by nockieboy).  The project suffered some feature creep, including a full SD-card interface, so throwing a PSG in from the 1980's didn't
seem like too much of a stretch!

This project sprung from Jose Tejada's work and full credit goes to him for the original jt49 project.  Neither myself nor BrianHG make any
claims to any of the original work, but we have enhanced and modified it as detailed below (and in great detail in the eevBlog forum mentioned
below).

Enhancements by BrianHG   : https://github.com/BrianHGinc
          and Nockieboy   : https://github.com/nockieboy
          
Technical info/specs here : https://www.eevblog.com/forum/fpga/fpga-vga-controller-for-8-bit-computer/msg4366420/#msg4366420

You can also find us here : https://www.eevblog.com/forum/fpga/

### Included source code:
- BHG_clock_fp_div.sv      -> Precision floating point clock divider to generate any desired system clock down to the Hz.
- I2S_transmitter.sv       -> I2S digital audio transmitter for all Audio DACs/Codecs and HDMI transmitters.
- BHG_jt49.v               -> An enhanced modified version of the original jt49.v offering higher # of bits for the sound output channels.
- BHG_jt49_exp_tablegen.v  -> A generator the precision volumetric tables.  Generates the BHG_jt49_exp_lut.vh file.
- BHG_jt49_exp_lut.vh      -> The parameter table generated after Sim running the BHG_jt49_exp_tablegen.v.
- BHG_jt49_exp.v           -> A replacement for the original jt49_exp.v using the tables in BHG_jt49_exp_lut.vh.
- BHG_jt49_filter_mixer.sv -> Offers programmable channel mixing levels (use 2 for custom stereo), DC filter with clamp, and treble control.

### Enhancements include:
- Stereo sound with control registers for channel mixing volume and phase.
- Registers for Treble and Bass adjustments.
- Smart DC filtering allowing lower frequency output while managing peaks and switch on/off pops when necessary.
- Improved precision 8 thru 14 bit exponential DAC support.  (10 bit almost exactly replicates the YM2149 normalized output voltage).
- Precision floating point system clock divider offering parameter select-able PSG reference frequencies with accuracy down to the Hz.
- Integrated standard I<sup>2</sup>S transmitter output with resampling & floating point system clock divider offering DAC Khz settings down to the Hz.
- Functional simulation setup for Modelsim, with example YM2149 presets and full outputs with analog waveforms.
- Simulation also includes a switch to run Jose Tejada's original jt49 project for direct comparison.


## Parameters & Ports
The project is instantiated in a top-level module as follows:
```
YM2149_PSG_system #(

   .CLK_IN_HZ       (      CMD_CLK_HZ ),   // Input system clock frequency
   .CLK_I2S_IN_HZ   (   DDR3_CLK_HZ/2 ),   // Input I2S clock frequency
   .CLK_PSG_HZ      (         1000000 ),   // Desired PSG clock frequency (Hz)
   .I2S_DAC_HZ      (           48000 ),   // Desired I2S clock frequency (Hz)
   .YM2149_DAC_BITS (               9 ),   // PSG DAC bit precision, 8 through 12 bits, the higher the bits, the higher the dynamic range.
                                           // 10 bits almost perfectly replicates the YM2149 DA converter's Normalized voltage.
                                           // With 8 bits, the lowest volumes settings will be slightly louder than normal.
                                           // With 12 bits, the lowest volume settings will be too quiet.
   .MIXER_DAC_BITS  (              16 )    // The number of DAC bits for the BHG_jt49_filter_mixer core and output.

) ARYA (

   .clk             (      CMD_CLK ),
   .clk_i2s         (  DDR3_CLK_50 ),
   .reset_n         (       ~reset ),
   .addr            (   r_psg_addr ), // register address
   .data            ( r_psg_data_i ), // data IN to PSG
   .wr_n            ( !r_psg_wr_en ), // data/addr valid

   .dout            ( r_psg_data_o ), // PSG data output
   .i2s_sclk        (      s0_bclk ), // I2S serial bit clock output
   .i2s_lrclk       (      s0_wclk ), // I2S L/R output
   .i2s_data        (      s0_data ), // I2S serial audio out
   .sound           (              ), // parallel audio out, mono or left channel
   .sound_right     (              )  // parallel audio out, right channel

);
```

## HDL project notes
Only include one of the following:

`include "YM2149_PSG_system.sv"`  This will simulate the new BrianHG & Nockieboy YM2149_PSG_system.

or:

`include "YM2149_PSG_jt49.sv"`    This will simulate the original jt49 YM2149 PSG source code
                              from [Jose Tejada's GitHub repository](https://github.com/jotego/jt49).
                              
    Remember, parameter YM2149_DAC_BITS must be set to 8 when using Jose Tejada's version!

    Patched files:
    - 'jt49_dly.v', found a few bugs in the original HDL, see lines: 29, 30, 31, & 39.

    Also found clip-inversion overflow bug in jt49_mave.v & jt49_dcrm2.v, which the DC filter seems to sometimes patch. Though this may
    be looked at by Jose Tejada, it is no longer in use because of the new 'BHG_jt49_filter_mixer.sv' replacement.

## Build
This project is tested and verified in ModelSim and on an Arrow DECA (MAX 10M50) FPGA development board with attached 8-bit host computer.

# YM2149_PSG_system

An advanced YM2149 / AY-3-8910 Programmable Sound Generator.  Offers dual PSGs, programmable stereo mixer with bass and treble controls, standard
I<sup>2</sup>S 44.1KHz or 48KHz 16-bit audio out, and built-in very accurate floating point system clock divider / generator.

## A Programmable Sound Generator based on [Jose Tejada's GitHub repository](https://github.com/jotego/jt49)

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
- Improved precision 8 thru 10 bit exponential DAC support.  (10 bit almost exactly replicates the YM2149 normalized output voltage).
- Precision floating point system clock divider offering parameter select-able PSG reference frequencies with accuracy down to the Hz.
- Integrated standard I<sup>2</sup>S transmitter output with resampling & floating point system clock divider offering DAC Khz settings down to the Hz.
- Functional simulation setup for Modelsim, with example YM2149 presets and full outputs with analog waveforms.
- Simulation also includes a switch to run Jose Tejada's original jt49 project for direct comparison.
- Included extensive Modelsim `setup_xxx.do` batch files and `YM2149_PSG_system_tb.sv`, which simulate multiple settings of the PSG and mixer with preset
sounds to view the filter's effects and a DAC ramp visualization to compare to the `YM2149_dac_normalized_voltage.png`.


## Parameters & Ports
The project is instantiated in a top-level module as follows:
```
YM2149_PSG_system #(

   .CLK_IN_HZ       (    50000000 ), // Input system clock frequency
   .CLK_I2S_IN_HZ   (   200000000 ), // Input I2S clock frequency
   .CLK_PSG_HZ      (     1000000 ), // Desired PSG clock frequency (Hz)
   .I2S_DAC_HZ      (       48000 ), // Desired I2S clock frequency (Hz)
   .YM2149_DAC_BITS (           9 ), // PSG DAC bit precision, 8 through 12 bits, the higher the bits, 
                                     // the higher the dynamic range.
                                     // 10 bits almost perfectly replicates the YM2149 DA converter's
                                     // Normalized voltage. With 8 bits, the lowest volumes settings
                                     // will be slightly louder than normal. With 12 bits, the lowest
                                     // volume settings will be too quiet.
   .MIXER_DAC_BITS  (          16 )  // The number of DAC bits for the BHG_jt49_filter_mixer core and
                                     // output.

) ARYA (

   .clk             (     CLK_50m ), // Master clock for interfacing with the PSG.
   .clk_i2s         (    CLK_200m ), // Reference clock for the I2S generator's output. Should be 
                                     // 148.5MHz or higher.
   .reset_n         (     reset_n ), // Active-LOW reset.
   .addr            (    psg_addr ), // PSG register address for data reads/writes.
   .data            (  psg_data_i ), // 8-bit data IN to PSG for register writes.
   .wr_n            ( psg_wr_en_n ), // Active-LOW write enable.

   .dout            (  psg_data_o ), // PSG data output for register reads.
   .i2s_sclk        (     s0_bclk ), // I2S serial bit clock output.
   .i2s_lrclk       (     s0_wclk ), // I2S L/R output.
   .i2s_data        (     s0_data ), // I2S serial audio out.
   .sound           (             ), // parallel audio out, mono or left channel.
   .sound_right     (             )  // parallel audio out, right channel.

);
```

## HDL project notes
You can switch between the new and improved PSG system simulation and a simulation of the original version by Jose Tejada by 
commenting-out the appropriate define on lines 48 or 49 in `YM2149_PSG_system_tb.sv`:
```
//`define use_legacy_jt49         // Simulate original jt49 hdl.
`define use_YM2149_PSG_system   // Simulate new PSG_System.
```                           

Remember, parameter YM2149_DAC_BITS must be set to 8 when using Jose Tejada's version!

Patched files:
- `jt49_dly.v` - found a few bugs in the original HDL, see lines: 29, 30, 31, & 39.
- `jt49_mave.v` & `jt49_dcrm2.v` - found clip-inversion overflow bugs, which the DC filter seems to sometimes patch. Though this
may be looked at by Jose Tejada, it is no longer in use here because of the new `BHG_jt49_filter_mixer.sv` replacement.

If you want zero jitter for the clk_i2s input, you should use a source PLL clock which is 256x, or higher, multiples of the source clock
frequency.  This is the one case where you may use frequencies below 148.5MHz - e.g., if you want 48MHz I<sup>2</sup>S audio with no
jitter, use 12.288MHz, or 2x or 4x that, etc..

## Build
This project has been built in Quartus 20.1, tested and verified in ModelSim and on an Arrow DECA (MAX 10M50) FPGA development board with attached 8-bit host computer
running Z80 CP/M.  A number of music files have been tested, including game soundtracks, with great results.

See the [eevBlog forum](https://www.eevblog.com/forum/fpga/) for some .mp3 samples and more.

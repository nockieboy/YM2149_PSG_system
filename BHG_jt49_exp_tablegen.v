/*  

This source code was designed to generate a new jt49_exp.v source based
on look-up tables since Quartus cant handle the 'real' floating point math. 

BHG_jt49_exp_tablegen.v v1.0, Aug 6, 2022 by Brian Guralnick.

This code is free to use.  Just be fair and give credit where it is due.

******************************************************************
*** This code was written by BrianHG providing an optional     ***
*** volume decibel attenuation with taper optimization for     ***
*** the first few DAC volume steps.                            ***
*** This code will generate LUT tables for 8 to 12 bit DACs.   ***
******************************************************************

10 bits almost perfectly replicates the YM2149 DA converter's Normalized voltage.
With 8 bits, the lowest volumes settings will be slightly louder than normal.
With 12 bits, the lowest volume settings will be too quiet.

*/

module BHG_jt49_exp_tablegen ();

// Correct low volume dynamic range adjusted for the # of bits the DAC contains.
// 15        = Best low volume taper optimization for the DAC's bit depth.
// >15 to 30 = less dynamic volume range.
// <15 to  5 = too much dynamic range for the DAC resolution.  IE: first few volume steps will be mute and contain repeats.

localparam real      LSB_DB_CORRECTION [8:12] = '{15,14,13,12,11} ;

integer DAC_BITS = 8;
// Make a lookup table with this LOG computation which defines the DAC's LSB SNR.
// 20*log(1/(2^DAC_BITS-1))

localparam real       DAC_LSB_DB [8:12] =  '{ -48.1308,-54.1684,-60.1975,-66.2224,-72.2451 } ;

// Select either the user set volume attenuation or,
// automatically select from the DAC_LSB_DB lookup table -15db
// so that the minimum volume bits actually increment at volumes 0,1,2,3...
// without repeats.  IE: More DAC bits, the better the dynamic range.

`define VOL_factor ( ( DAC_LSB_DB[DAC_BITS]+LSB_DB_CORRECTION[DAC_BITS] ) /31 )      // factor the decibel range over the 5 bit volume range.

// Volume attenuation to linear amplitude formula with -infinity/basement mute correction.
`define atten_dbv(x)    ( (10**(((31-x)*`VOL_factor)/20) *(2**DAC_BITS-1))   ) 
`define gain_fix        ( (2**DAC_BITS-1) / (`atten_dbv(31) - `atten_dbv(0)) )
`define dac_vout(z)     ( (`atten_dbv(z) - `atten_dbv(0)) * `gain_fix        )


integer signed dlut ;
reg [11:0]     dlut_unsigned ;

integer fout_pointer = 0;
string  destination_file_name = "BHG_jt49_exp_lut.vh" ;
string  num_string [8:12]     = '{"8 ","9 ","10","11","12"};


reg [7:0] LDC[8:12] = LSB_DB_CORRECTION[8:12] ;

initial begin


   fout_pointer= $fopen(destination_file_name,"w");   // Open that file name for writing.
   if (fout_pointer==0) begin
        $display("\nCould not open log file '%s' for writing.\n",destination_file_name);
        $stop;
   end else begin


   $fwrite(fout_pointer,"\
\/************************************************************************************************************************************* \n\n\
This DAC LUT table was created with the 'BHG_jt49_exp_tablegen.v', v1.0, Aug 6, 2022.\n\
                                         It was rendered using Modelsim.\n\
                                         by Brian Guralnick.\n\
                                         https://github.com/BrianHGinc\n\
\n\
Table generated using a LSB_DB_CORRECTION setting of [8:12] :'{%d,%d,%d,%d,%d}.\n\
                                                              *** 15 is optimum for an 8 bit dac ***.\n\
\n\
This code is free to use.  Just be fair and give credit where it is due.\n\
\n\
******************************************************************\n\
*** This code was written by BrianHG providing an optional     ***\n\
*** volume decibel attenuation with taper optimization for     ***\n\
*** the first few DAC volume steps.                            ***\n\
*** This code will generate LUT tables for 8 to 12 bit DACs.   ***\n\
******************************************************************/\n\
\n",8'(LDC[8]),8'(LDC[9]),8'(LDC[10]),8'(LDC[11]),8'(LDC[12]) );


        for (DAC_BITS=8;DAC_BITS<13;DAC_BITS++) begin

            dlut = DAC_LSB_DB[DAC_BITS] ;

            $fwrite(fout_pointer,"\/\/ *************************************************************************************************************************************\n");
            $fwrite(fout_pointer,"\/\/ *** %s bit DAC LUT with a dynamic range of%d decibels.\n",num_string[DAC_BITS], 8'(dlut) );
            $fwrite(fout_pointer,"\/\/ *************************************************************************************************************************************\n");

            $fwrite(fout_pointer,"localparam logic [15:0] dlut_%s [0:31] = '{",num_string[DAC_BITS]);

            for (int i=0;i<32;i++) begin

                                    dlut          = `dac_vout(i) ;
                                    dlut_unsigned = dlut ;

                                    $fwrite(fout_pointer,"%d",13'(dlut_unsigned)) ;

                                             if (i==15) $fwrite(fout_pointer,",\n                                           ") ;
                                        else if (i<31)  $fwrite(fout_pointer,",") ;
                                        else            $fwrite(fout_pointer,"};\n") ;
                                    end

        end // for dacbits

    $fwrite(fout_pointer,"\n");
    $fwrite(fout_pointer,"\/\/ **********************************************\n");
    $fwrite(fout_pointer,"\/\/ *** Coalesce the 5 tables into a 2D array. ***\n" );
    $fwrite(fout_pointer,"\/\/ **********************************************\n");
    $fwrite(fout_pointer,"localparam logic [15:0] dlut_sel [8:12][0:31] = '{ dlut_8, dlut_9, dlut_10, dlut_11, dlut_12 };");

    $fwrite(fout_pointer,"\n\n\/\/ *** Table End.\n\n");
    $fclose(fout_pointer);
    fout_pointer = 0;

    $display("\n\n  ************************************************************************************************");
    $display("  *** Finished generating DAC LUT header file '%s'.",destination_file_name);
    $display("  ************************************************************************************************");

    end // open file



end // initial


endmodule



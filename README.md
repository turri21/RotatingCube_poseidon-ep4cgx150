# -=(Rotating Cube Demo for Poseidon)=-

This is a demonstration of a 16-Voice Polyphonic MIDI Synthesizer along with a midi file parser, a 64-star parallax starfield rendered entirely in combinatorial logic, a 3D wireframe shapeshifting cube and a text scroller which has its own font rom. The demo works in "bare metal" without the need of a CPU and/or of the MiST firmware & framework!

It comes along with a dedicated framebuffer, an I2S module, a Bresenham line-draw engine as well as the required VGA timing logic.

Ported from Senhor FPGA and synthesized in Quartus v17.0.2

------------------------------

Instructions for developers.

In the first line of text.py you may enter your own message inside the quotes:

msg = "Hello World!"

After you save it and run it, the output will be 3 localparam lines that should replace the respective ones in text_scroller.sv 

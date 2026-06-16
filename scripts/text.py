msg = "  * ROTATING CUBE DEMO FOR POSEIDON FPGA !!! * -- Greetings to all FPGA freaks on Telegram! --"

# ASCII encode and reverse so char[0] sits at bits [7:0]
raw   = msg.encode('ascii')
hex_str = ''.join(f'{b:02x}' for b in raw[::-1])

n     = len(msg)
bits  = n * 8
pix   = n * 8   # 8 pixels wide per char

print(f'    localparam [15:0] MSG_LEN = 16\'d{n};')
print(f'    localparam [15:0] MSG_PIX = 16\'d{pix};')
print(f'    localparam [{bits-1}:0] MSG_ROM = {bits}\'h{hex_str};')

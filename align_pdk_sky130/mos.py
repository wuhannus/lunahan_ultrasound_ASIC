"""sky130 MOS primitive cell generator for ALIGN."""
from align.pdk.finfet import MOS, CanvasPDK

class sky130_MOS(MOS):
    """Override MOS for sky130 planar CMOS."""
    
    def __init__(self):
        super().__init__()
        self.poly_layer = 68
        self.n_diff_layer = 65
        self.p_diff_layer = 66
        self.nwell_layer = 64
        self.cont_layer = 70
        self.m1_layer = 71
        self.m2_layer = 72
    
    def generate_fingers(self, canvas, nf, w, l, device_type):
        """Generate planar MOSFET fingers (no fins)."""
        fp = int(w * 1000)  # finger width in nm
        l_nm = int(l * 1000) if isinstance(l, str) and 'u' in l else int(l) * 1000
        
        for i in range(nf):
            # Diffusion
            canvas.rect(
                self.n_diff_layer if device_type == 'NMOS' else self.p_diff_layer,
                i * (fp + 200) + 100, 500, fp, l_nm
            )
            # Poly gate
            canvas.rect(
                self.poly_layer,
                i * (fp + 200) + 100 - 250, 500 - 250, fp + 500, l_nm + 500
            )
            # Contacts
            canvas.rect(
                self.cont_layer,
                i * (fp + 200) + 100 + int(fp * 0.3), 500 + l_nm + 60, 170, 170
            )
            canvas.rect(
                self.cont_layer,
                i * (fp + 200) + 100 + int(fp * 0.3), 440, 170, 170
            )

# Register in ALIGN
NMOS = sky130_MOS
PMOS = sky130_MOS

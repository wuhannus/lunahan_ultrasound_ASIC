"""sky130 parameter generation for ALIGN."""
import math

def gen_param(model, w, l, nfin):
    """
    Generate ALIGN device parameters from SPICE W/L/nfin.
    sky130: planar CMOS (nfin = number of fingers)
    """
    unit_size = 12
    
    # Width per finger in µm -> ALIGN units
    w_um = w if isinstance(w, (int, float)) else float(str(w).replace('u',''))
    l_nm = l * 1000 if isinstance(l, (int, float)) else float(str(l).replace('u','')) * 1000
    
    # Number of fingers
    nf = max(1, nfin)
    
    # Device width in ALIGN units (multiples of unit_size)
    width_units = max(1, int(w_um * 1000 / unit_size))
    
    # MOS stack: sky130 uses single-stack (no FinFET fins)
    stack = 1
    
    return {
        'w': w_um,
        'l': l,
        'nf': nf,
        'stack': stack,
        'parallel': 1,
        'model': model
    }

def get_MosParameters(model, w, l, nfin):
    """Convert to ALIGN PrimitiveCell format."""
    params = gen_param(model, w, l, nfin)
    return {
        'DeviceType': 'NMOS' if 'n' in model.lower() else 'PMOS',
        'STACK': params['stack'],
        'NFIN': params['nf'],
        'NF': params['nf'],
        'W': params['w'],
        'L': params['l'],
    }

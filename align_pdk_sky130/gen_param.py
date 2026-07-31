"""sky130 parameter generation for ALIGN."""
import json, logging, math
from copy import deepcopy
logger = logging.getLogger(__name__)

def gen_param(subckt, primitives, pdk_dir):
    """Generate primitive parameters from subcircuit definition."""
    for inst in subckt.elements:
        if inst.model.lower().startswith('nmos') or inst.model.lower().startswith('nm'):
            model = 'nmos_rvt'
            device = 'NMOS'
        elif inst.model.lower().startswith('pmos') or inst.model.lower().startswith('pm'):
            model = 'pmos_rvt'
            device = 'PMOS'
        else:
            continue
        
        # Extract W, L from instance parameters
        w = float(str(inst.parameters.get('w', '1u')).replace('u',''))
        l = float(str(inst.parameters.get('l', '1u')).replace('u',''))
        nf = int(inst.parameters.get('nf', 1))
        
        primitive = {
            'name': inst.name,
            'DeviceType': device,
            'NF': nf,
            'STACK': 1,
            'W': w,
            'L': l,
            'model': model
        }
        primitives[inst.name] = primitive
    
    return primitives

def get_MosParameters(model, w, l, nfin):
    return {'DeviceType': 'NMOS' if 'n' in model else 'PMOS', 'NF': max(1, nfin), 'STACK': 1, 'W': w, 'L': l}

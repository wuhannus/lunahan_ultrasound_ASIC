#!/usr/bin/env python3
"""
mom_cap.py — inter-finger Metal-Oxide-Metal capacitor generator (sky130).

Builds a MOM cap from interdigitated MET3 (70) / MET4 (71) fingers:
  plate A: even fingers (node top), plate B: odd fingers (node bottom)
  plus connecting bus bars on each plate.

Returns a gdsfactory Component with ports `top` (plate A) and `bottom`
(plate B), so it integrates with the glayout / analog-router flow.

Layers (glayout/Magic): MET3 = (70,20), MET4 = (71,20)
"""
import gdstk
import gdsfactory as gf


class MomCap:
    def __init__(self, length=5.0, fingers=10, finger_width=0.3,
                 finger_space=0.3, bus_width=0.5):
        self.length = length
        self.fingers = fingers
        self.fw = finger_width
        self.fs = finger_space
        self.bus = bus_width
        self.pitch = self.fw + self.fs
        self.width = self.fingers * self.pitch + self.bus

    def build(self, name="MOMCAP", met3=(70, 20), met4=(71, 20)):
        c = gf.Component(name)
        # fingers: even -> plate A (met4), odd -> plate B (met3)
        for i in range(self.fingers):
            x0 = self.bus / 2 + i * self.pitch
            x1 = x0 + self.fw
            if i % 2 == 0:
                c.add_polygon([(x0, 0), (x1, 0), (x1, self.length),
                               (x0, self.length)],
                              layer=(met4[0], met4[1]))
            else:
                c.add_polygon([(x0, 0), (x1, 0), (x1, self.length),
                               (x0, self.length)],
                              layer=(met3[0], met3[1]))
        # bus bars: plate A bottom (met4), plate B top (met3)
        c.add_polygon([(0, -self.bus), (self.width, -self.bus),
                       (self.width, 0), (0, 0)],
                      layer=(met4[0], met4[1]))
        c.add_polygon([(0, self.length), (self.width, self.length),
                       (self.width, self.length + self.bus),
                       (0, self.length + self.bus)],
                      layer=(met3[0], met3[1]))
        # ports on the bus bars
        c.add_port(name="top", center=(self.width / 2, self.length + self.bus / 2),
                   width=self.bus, orientation=90, layer=(met3[0], met3[1]))
        c.add_port(name="bottom",
                   center=(self.width / 2, -self.bus / 2),
                   width=self.bus, orientation=-90, layer=(met4[0], met4[1]))
        return c

    @property
    def port_a(self):
        return (self.width / 2, -self.bus / 2)

    @property
    def port_b(self):
        return (self.width / 2, self.length + self.bus / 2)


def mom_cap_area(target_fF, density=0.2):
    return target_fF / density


if __name__ == "__main__":
    c = MomCap(length=10.0, fingers=12)
    cell = c.build()
    print(f"width={c.width:.1f} height={c.length + c.bus:.1f} "
          f"ports={list(cell.ports.keys())}")

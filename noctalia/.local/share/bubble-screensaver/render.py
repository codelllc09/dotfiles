"""离线生成黑底泡泡循环。用法：python render.py 输出.webm（需要 NumPy、Pillow、FFmpeg）。"""
import argparse
import math
import random
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

WIDTH, HEIGHT = 1536, 960
SECONDS, FPS = 48, 30
SEED = 271828


def bubble_sprite(radius, hue):
    """彩色薄膜、明暗边缘和两处反光。黑色透明区域允许泡泡相互叠加。"""
    pix = np.arange(-radius-1, radius+2, dtype=np.float32) / radius
    x, y = np.meshgrid(pix, pix)
    distance = np.hypot(x, y)
    angle = np.arctan2(y, x)
    bands = hue + 2*angle + 0.65*np.sin(3*angle) + 5*(1-distance)
    wavelengths = np.array([0, -2.09, 2.09], dtype=np.float32)
    film = 0.52 + 0.48*np.cos(bands[..., None] + wavelengths)
    rim = np.exp(-((distance-0.905)/0.078)**2)
    edge = np.exp(-((distance-0.975)/0.016)**2)
    light = (0.5 + 0.5*np.cos(angle + 2.2))**3
    # 椭圆反光沿左上方球面切线延展。
    dx, dy = x+0.36, y+0.64
    u, v = 0.86*dx-0.51*dy, 0.51*dx+0.86*dy
    shine = np.exp(-((u/0.29)**2 + (v/0.069)**2)*1.45)
    upper_arc = np.exp(-((distance-0.87)/0.018)**2) * np.maximum(0, np.cos(angle+2.13))**22
    lower_arc = np.exp(-((distance-0.90)/0.026)**2) * np.maximum(0, np.cos(angle-0.97))**14
    reflection = np.clip(0.98*shine + 0.69*upper_arc + 0.37*lower_arc, 0, 1)
    rgb = film * (72 + 146*distance[..., None]) + (32 + 42*light)[..., None]
    rgb = rgb*(1-reflection[..., None]) + 255*reflection[..., None]
    alpha = 0.055 + 0.13*distance**3 + 0.61*rim + 0.66*edge + 0.95*reflection
    coverage = np.clip((1-distance)*radius + 0.5, 0, 1)
    rgba = np.dstack((np.clip(rgb, 0, 255), 255*coverage*np.clip(alpha, 0, 1)))
    return Image.fromarray(rgba.astype(np.uint8))


@dataclass
class Track:
    span: float
    margin: int
    turns: int
    offset: float
    waves: tuple

    def position(self, phase):
        # 整数圈数与整数谐波让位置、速度在周期两端自然相接。
        displacement = sum(a*math.sin(k*phase+p) for a,k,p in self.waves)
        pos = self.offset + self.span*self.turns*phase/math.tau + displacement
        return pos % self.span - self.margin


def track(extent, radius, turns, rng):
    margin = radius + 6
    span = extent + 2*margin
    waves = tuple((extent*rng.uniform(low, high), freq, rng.uniform(0, math.tau))
                  for freq,low,high in [(1, 0.11, 0.22), (2, 0.045, 0.10), (3, 0.018, 0.045)])
    return Track(span, margin, turns, rng.uniform(0, span), waves)


def make_scene():
    rng = random.Random(SEED)
    scene = []
    for _ in range(14):
        radius = rng.randint(32, 78)
        horizontal = rng.choice((-2, -1, 1, 2))
        vertical = rng.choice((-2, -1, 1, 2))
        scene.append((bubble_sprite(radius, rng.uniform(0, math.tau)),
                      track(WIDTH, radius, horizontal, rng),
                      track(HEIGHT, radius, vertical, rng)))
    return scene


def frame_at(scene, number):
    phase = math.tau * (number % (SECONDS*FPS)) / (SECONDS*FPS)
    image = Image.new("RGB", (WIDTH, HEIGHT))
    for sprite, horizontal, vertical in scene:
        left = round(horizontal.position(phase)) - sprite.width//2
        top = round(vertical.position(phase)) - sprite.height//2
        image.paste(sprite, (left, top), sprite)
    return image


def render(output):
    scene = make_scene()
    with tempfile.TemporaryDirectory(dir=output.parent) as directory:
        encoded = Path(directory) / "bubbles.webm"
        command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
                   "-filter_threads", "1", "-f", "rawvideo", "-pixel_format", "rgb24",
                   "-video_size", f"{WIDTH}x{HEIGHT}", "-framerate", str(FPS),
                   "-i", "pipe:0", "-an", "-c:v", "libvpx", "-threads", "1",
                   "-deadline", "realtime", "-cpu-used", "4", "-crf", "8", "-b:v", "1800k",
                   "-pix_fmt", "yuv420p", "-g", str(FPS*2), str(encoded)]
        with subprocess.Popen(command, stdin=subprocess.PIPE) as encoder:
            try:
                # 只编码 [0, T)；循环时第一帧恰好是末帧的下一步。
                for n in range(SECONDS*FPS):
                    encoder.stdin.write(frame_at(scene, n).tobytes())
                encoder.stdin.close()
            except BaseException:
                encoder.kill()
                raise
            if encoder.wait():
                raise RuntimeError("FFmpeg 编码失败")
        encoded.replace(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    render(parser.parse_args().output)

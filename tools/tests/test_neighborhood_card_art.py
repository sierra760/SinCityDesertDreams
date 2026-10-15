# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reject atlas fragments that shift the subject within a drawn card image."""
from collections import deque
import json
from pathlib import Path
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "game/assets/desert-dreams-casino-art"


def principal_bounds(image):
    width, height = image.size
    mask = bytearray(a >= 128 for a in image.getchannel("A").get_flattened_data())
    largest = (0, None)
    for start in range(len(mask)):
        if not mask[start]:
            continue
        queue = deque([start]); mask[start] = 0
        area = 0
        left = right = start % width
        top = bottom = start // width
        while queue:
            index = queue.popleft(); x, y = index % width, index // width
            area += 1
            left = min(left, x); right = max(right, x)
            top = min(top, y); bottom = max(bottom, y)
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < width and 0 <= yy < height:
                    neighbor = yy * width + xx
                    if mask[neighbor]:
                        mask[neighbor] = 0; queue.append(neighbor)
        if area > largest[0]:
            largest = (area, (left, top, right + 1, bottom + 1))
    return largest[1]


class NeighborhoodCardArtTests(unittest.TestCase):
    def test_woolier_cards_center_the_principal_subject_not_neighbor_fragments(self):
        catalog = json.loads((ART / "catalog.json").read_text())["sets"]["woolier"]["assets"]
        for name in ("court-jack", "court-queen", "court-king", "card-back"):
            with self.subTest(asset=name), Image.open(ART / "woolier" / (name + ".png")) as image:
                self.assertEqual(image.mode, "RGBA")
                subject = principal_bounds(image)
                self.assertIsNotNone(subject)
                x, y, width, height = catalog[name]["content_region"]
                for center, expected, span in (
                    (x + width / 2, (subject[0] + subject[2]) / 2, subject[2] - subject[0]),
                    (y + height / 2, (subject[1] + subject[3]) / 2, subject[3] - subject[1]),
                ):
                    self.assertLessEqual(abs(center - expected), max(2, span * .025),
                                         name + ": neighboring pixels shift the visible card artwork")


if __name__ == "__main__":
    unittest.main()

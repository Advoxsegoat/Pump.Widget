"""What the tests look at in a made portrait, written here and not taken from the tool (so that the tool's own check is not the yardstick
of itself): the picture's ink, whether a straight line is left across it, how much of a known drawing is present and how much ink lies
where the drawing has none."""
import numpy as np
from PIL import Image, ImageFilter


def ink_of(rgb):
    """The pencil of a portrait: darker than 110 of 255 on average."""
    return np.asarray(rgb, dtype=np.float32).mean(axis=-1) < 110.0


def dilate(mask, size):
    return np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(size))) > 0


def lines_left(line, threshold=0.1):
    """The most any sheared row is inked: the picture's ink (above `threshold`) sheared along every slope within 6 degrees of level,
    for each the share of the columns of the middle 80% that hold ink in the same 3-row band; returns (share, slope, row). A rule left
    in the picture is a line across most of it; a stroke of the drawing is not."""
    h, w = line.shape
    ink = line > threshold
    ys, xs = np.nonzero(ink[:, int(0.1 * w): int(0.9 * w)])
    xs = xs + int(0.1 * w)
    xc = xs - w / 2.0
    n = int(0.8 * w)
    best = (0.0, 0.0, 0)
    for slope in np.arange(-0.105, 0.1051, 0.0025):
        for shift in (0.0, 1.5):
            rows = np.floor((ys - slope * xc + shift) / 3.0).astype(np.int64) + 400
            keys = np.unique(rows * (w + 1) + xs)
            counts = np.bincount(keys // (w + 1))
            at = int(np.argmax(counts))
            if counts[at] / n > best[0]:
                best = (counts[at] / n, float(slope), (at - 400) * 3)
    return best


def grey_of(rgb):
    """Any visible grey line of a portrait: darker than 200 of 255 on average (a rule's last trace is about 180)."""
    return np.asarray(rgb, dtype=np.float32).mean(axis=-1) < 200.0


def against_truth(rgb, truth_card):
    """(the share of the known drawing's pixels that have pencil within 2 pixels, the count of grey pixels more than 6 pixels from the drawing,
    how much more of the picture's width the most inked sheared row has than the same row of the drawing alone has)."""
    present = float(dilate(ink_of(rgb), 5)[truth_card].mean())
    grey = grey_of(rgb)
    stray = int((grey & ~dilate(truth_card, 13)).sum())
    extra = lines_left(grey.astype(np.float32), 0.5)[0] - lines_left(truth_card.astype(np.float32), 0.5)[0]
    return present, stray, extra

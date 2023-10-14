import argparse
import json
import matplotlib.pyplot as plt
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("file", help="JSON file with benchmark results")
parser.add_argument("--title", help="Plot title")
parser.add_argument(
    "--labels", help="Comma-separated list of entries for the plot legend"
)
parser.add_argument("-o", "--output", help="Save image to the given filename.")

args = parser.parse_args()

with open(args.file) as f:
    results = json.load(f)["results"]

if args.labels:
    labels = args.labels.split(",")
else:
    labels = [b["command"] for b in results]
times = [b["mean"] for b in results]

fig, ax = plt.subplots()

# Example data
y_pos = np.arange(len(labels))
error = [b["stddev"] for b in results]

ax.barh(y_pos, times, xerr=error, align='center')
ax.set_yticks(y_pos, labels=labels)
ax.invert_yaxis()  # labels read top-to-bottom
ax.set_xlabel('Time (s)')

if args.title:
    plt.title(args.title)

if args.output:
    fig = plt.gcf()
    fig.tight_layout()
    plt.savefig(args.output)
else:
    plt.show()

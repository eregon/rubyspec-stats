import yaml

with open('per_year_per_impl.yml', 'r') as file:
    per_year_per_impl = yaml.safe_load(file)

# From https://matplotlib.org/stable/gallery/lines_bars_and_markers/stackplot_demo.html#sphx-glr-gallery-lines-bars-and-markers-stackplot-demo-py

import matplotlib.pyplot as plt
import numpy as np

import matplotlib.ticker as mticker

# year = [1950, 1960, 1970, 1980, 1990, 2000, 2010, 2018]
# data = {
#     'Africa': [.228, .284, .365, .477, .631, .814, 1.044, 1.275],
#     'the Americas': [.340, .425, .519, .619, .727, .840, .943, 1.006],
#     'Asia': [1.394, 1.686, 2.120, 2.625, 3.202, 3.714, 4.169, 4.560],
#     'Europe': [.220, .253, .276, .295, .310, .303, .294, .293],
#     'Oceania': [.012, .015, .019, .022, .026, .031, .036, .039],
# }

year = list(per_year_per_impl.keys())
data = {}
for y, contribs in per_year_per_impl.items():
    total_that_year = sum(contribs.values())
    for impl, commits in contribs.items():
        impl = impl[1:]
        if impl not in data:
            data[impl] = []
        data[impl].append(commits / total_that_year)
        # data[impl].append(commits)

print(year)
print(data)

fig, ax = plt.subplots()
ax.stackplot(year, data.values(), labels=data.keys(), alpha=0.8)
ax.legend(loc='center right', reverse=True)
ax.set_title('Contributions to ruby/spec by group')
ax.set_xlabel('Year')
ax.set_ylabel('Proportion of all commits that year')

ax.set_xlim(min(year), max(year))
ax.set_ylim(0, 1)
ax.xaxis.set_major_locator(mticker.MultipleLocator(1))

plt.show()

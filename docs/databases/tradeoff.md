# The tradeoff being accepted

Logical dumps mean an RPO of the dump interval — up to one interval's writes lost
— and a slow, coarse restore: a logical reload rebuilds every index and replays
every row, which on a large database is measured in hours. Restores are rare here,
which is precisely why they tend to be emergencies; the recovery is slow when it
comes. This is a chosen tradeoff for a browse-heavy workflow, not an oversight.

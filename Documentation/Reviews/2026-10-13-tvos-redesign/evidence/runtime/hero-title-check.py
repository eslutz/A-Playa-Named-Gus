import sys
lines=[]
for line in open(sys.argv[1]):
 parts=line.strip().split(' ',4)
 if len(parts)==5:
  x,y,w,h=map(float,parts[:4]);lines.append((x,y,w,h,parts[4]))
headings=[r for r in lines if r[4]=='Recently Added Books']
assert headings,'First rail heading was not recognized'
heading=max(headings,key=lambda r:r[1])
titles=[r for r in lines if r[4]=='Peter and Wendy' and r[1]>heading[1]+heading[3]]
assert titles,'Complete hero title is not visible above the first rail'
assert max(r[1]+r[3] for r in titles)<0.97,'Hero title is above the TV safe top margin'
print('PASS: full hero title visible above first rail, inside top margin')

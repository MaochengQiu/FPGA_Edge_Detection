"""Independent local graph oracle. This is NOT full-image hysteresis."""
import collections
import numpy as np

def descriptor(magnitude,direction,nms_keep,high=50):
    low=(high+1)//2
    eligible=magnitude>=low
    candidate=nms_keep & eligible
    seed=candidate & (magnitude>=high)
    return eligible,candidate,seed,direction

def bridge_mask(eligible,candidate,direction):
    h,w=eligible.shape;out=np.zeros_like(eligible)
    pairs=((-1,0,1,0,2),(0,-1,0,1,0),(-1,-1,1,1,3),(1,-1,-1,1,1))
    for y in range(1,h-1):
        for x in range(1,w-1):
            if not eligible[y,x] or candidate[y,x]:continue
            for ax,ay,bx,by,normal in pairs:
                if candidate[y+ay,x+ax] and candidate[y+by,x+bx] and direction[y,x]==normal and direction[y+ay,x+ax]==normal and direction[y+by,x+bx]==normal:
                    out[y,x]=True;break
    return out

def local_link(eligible,candidate,seed,direction,min_component=3,min_seeds=3,bridge=True):
    h,w=candidate.shape;out=np.zeros_like(candidate)
    fill=bridge_mask(eligible,candidate,direction) if bridge else np.zeros_like(candidate)
    for y in range(2,h-2):
        for x in range(2,w-2):
            if not candidate[y,x] and not fill[y,x]:continue
            seeds=seed[y-2:y+3,x-2:x+3]
            if int(seeds.sum())<min_seeds:continue
            nodes=candidate[y-2:y+3,x-2:x+3].copy()
            nodes[1:4,1:4]|=fill[y-1:y+2,x-1:x+2]
            normals=direction[y-2:y+3,x-2:x+3]
            seen=np.zeros((5,5),bool);seen[2,2]=True;q=collections.deque([(2,2)])
            while q:
                yy,xx=q.popleft()
                for dy in (-1,0,1):
                    for dx in (-1,0,1):
                        ny,nx=yy+dy,xx+dx
                        if 0<=ny<5 and 0<=nx<5 and nodes[ny,nx] and not seen[ny,nx]:
                            # Symmetric tangent cone: reject the exact normal
                            # direction and a 90-degree jump between normals.
                            forbidden=0 if dy==0 else (2 if dx==0 else (1 if dx==dy else 3))
                            a=int(normals[yy,xx]);b=int(normals[ny,nx])
                            if a==forbidden or b==forbidden or (a-b)%4==2:continue
                            seen[ny,nx]=True;q.append((ny,nx))
            out[y,x]=int(seen.sum())>=min_component and int((seen&seeds).sum())>=min_seeds
    return out

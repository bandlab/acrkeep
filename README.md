# acrkeep

To maintain the size of your ACR, you should periodically delete stale and/or orphaned images. Some images may require 
 longer-term storage, another can be deleted more quickly. For example, in a test scenarios, your registry can quickly 
 be filled up with images that might never be deployed. From another side, in production, you should have ability to 
 suddenly roll several releases back 

`acrkeep` allows you to have different strategies to keep ACR storage space:

- `time` keeps latest images by update time for relative period. For example, to keep images which have been updated in 
 last three weeks 
- `top` keeps Top-_N_ images in the repository by update time
- `size` keeps latest images with summary size less than required. The strategy doesn't calculate size of shared layers 
 as unique value

You can combine strategies. For example, you can take 10 latest images and then keep modified in last one week with 
 total size less than 1Gb using just one command:
  
```
$: ./acrkeep.sh ... --top=10 --time=1W --size=1G ... 
```

All excluded images will be deleted by manifest digest: all associated tags referenced by the manifest are deleted, all 
 layer data for any layers unique to the image are deleted

By default, tool confirms deletion for each excluding image. If you trust it, you can force deletion without prompting  

Tool support runs in `dry run` mode. In this case it just displays images which are going to be deleted

## Alternatives

- [Delete images by absolute timestamp](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-delete#delete-digests-by-timestamp)
- [Delete orphaned images only](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-delete#delete-untagged-images)
- [Automatically purge images](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-auto-purge)

## Usage

Display complete help about this tool: 
```
$: ./acrkeep.sh --help
```

Dry run to keep images for last 2 weeks:
```
$: ./acrkeep.sh --name=... --repository=... --time=2w --dry-run
Task: to keep images by time: elder than 08/02/19 11:22:44
Going to delete images:
    orphaned(sha256:ee974d8f21b8a2f2cdb9405ff44931d31781ba7830816528c773df324eacf29e)
    orphaned(sha256:e9a9b5b326025f4bc4db083e23f3b11cd40fba08911af7001f7f073eac24c5e8)
    v0.1
    orphaned(sha256:846a712b5574e5fc99fb43419ad570af8a505c1e31635a73d42bf81857dc999d)
Action skipped in dry run mode
```

Dry run to keep images for last 18 days with summary size less than 5Gb:
```
$: ./acrkeep.sh --name=... --repository=... --time=18d --size=5G --dry-run -v
Task: to keep images by time: elder than 07/29/19 11:22:44
Task: to keep latest images with total size less than 5G (5368709120 bytes)
digest: sha256:ee974d8f21b8a2f2cdb9405ff44931d31781ba7830816528c773df324eacf29e
    size: 4919619507
    tag: latest
    updated: 1564515475
 >> decision: keep
digest: sha256:e9a9b5b326025f4bc4db083e23f3b11cd40fba08911af7001f7f073eac24c5e8
    size: 4919619622
    tag: None
    updated: 1564454068
 >> decision: delete because summary size 9839239129 more than 5368709120
digest: sha256:2a7b715572286dc7382430868e0dfb49df0e6d7d2015cd0e9fcf35fd86180c42
    size: 4862136383
    tag: v0.1
    updated: 1563486692
 >> decision: delete because summary size 72908451570 more than 5368709120
digest: sha256:846a712b5574e5fc99fb43419ad570af8a505c1e31635a73d42bf81857dc999d
    size: 4862145875
    tag: None
    updated: 1563483305
 >> decision: delete because summary size 77770597445 more than 5368709120
Going to delete images:
    orphaned(sha256:e9a9b5b326025f4bc4db083e23f3b11cd40fba08911af7001f7f073eac24c5e8)
    v0.1
    orphaned(sha256:846a712b5574e5fc99fb43419ad570af8a505c1e31635a73d42bf81857dc999d)
Action skipped in dry run mode
```

Run to keep five latest images:
```
$: ./acrkeep.sh --name=... --repository=... --top=5
Task: to keep top5 images
Nothing to clear
```

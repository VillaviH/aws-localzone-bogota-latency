# Is the AWS Local Zone in Bogotá worth it for your users?

[Español](README.es.md)

An open, reproducible latency test: **AWS Local Zone Bogotá** (`us-east-1-bog-1a`) vs **us-east-1 (Virginia)**, measured from *your* office, home or mobile network. Latency depends heavily on the ISP and the route, so the only way to know is to measure from where your users are.

<p align="center">
<img src="docs/demo.gif" width="49%" alt="Race with ISP-A fibre: Bogotá is faster">
<img src="docs/demo-movil.gif" width="49%" alt="Race with ISP-B mobile 5G: Bogotá is slower">
</p>

*The same request (write 1 MB to S3) in slow motion, using the measured medians. Left: ISP-A fibre. Right: ISP-B mobile 5G. Try it live: `demo.html`.*

First measurements were taken in Ecuador (ISP-A fibre, ISP-B mobile 5G). Results differ a lot per ISP; see `data/raw/` and the dashboard.

## What it deploys
The same small app is deployed twice, once in the Bogotá Local Zone and once in a regional AZ (Virginia), using only services AWS lists as available in the Bogotá Local Zone:
- **ELB**: one Application Load Balancer per location.
- **EC2**: one `c7i.large` per location (the cheapest type offered in the zone; no t3). Same Node app.
- **S3 One Zone-IA**: a directory bucket inside the Local Zone, and a regional bucket written with the same storage class in Virginia.
- VPC `10.10.0.0/24` with `/26` subnets. App endpoints: `/ping`, `/payload` (1 MB), `/api/read?obj=small|large` and `/api/write?obj=small|large` (S3), `/health` (no token). Everything else requires the header `x-probe-token`, otherwise 403.

## Architecture
```mermaid
flowchart LR
  C["Your client<br/>(laptop / phone)"] --> I((Internet))
  I --> LB1
  I --> LB2
  subgraph R["AWS us-east-1 · VPC 10.10.0.0/24"]
    subgraph LZ["Local Zone Bogotá (us-east-1-bog-1a)"]
      LB1["ELB (ALB)"] --> E1["EC2 c7i.large · Node"] --> S1[("S3 One Zone-IA<br/>directory bucket")]
    end
    subgraph VA["Regional AZ (us-east-1b)"]
      LB2["ELB (ALB)"] --> E2["EC2 c7i.large · Node"] --> S2[("S3 One Zone-IA<br/>regional bucket")]
    end
  end
```

## Requirements
- An AWS account with the **Bogotá Local Zone opted in**:
  ```
  aws ec2 describe-availability-zones --region us-east-1 --all-availability-zones \
    --filters Name=zone-type,Values=local-zone --query "AvailabilityZones[?contains(ZoneName,'bog')]"
  aws ec2 modify-availability-zone-group --region us-east-1 --group-name us-east-1-bog-1 --opt-in-status opted-in
  ```
- Terraform >= 1.5, AWS CLI, `curl`, `bash` (Windows: use WSL). Optional: `mtr`, `k6`.

## Quick start
```
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # set your aws_profile
terraform init && terraform apply
terraform output                                # IPs
export PROBE_TOKEN=$(terraform output -raw probe_token)
cd ../..
./scripts/measure.sh bogota   <BOGOTA_IP>   <ISP> <fibra|movil> 100 2 &
./scripts/measure.sh virginia <VIRGINIA_IP> <ISP> <fibra|movil> 100 2 &
wait
```
Use your real ISP name instead of `<ISP>` (e.g. `MYISP`), keep it consistent, and use `movil` for mobile/hotspot. Run `sudo mtr -rwbzc 50 <IP>` to see the route.

**When finished: `terraform destroy`.** Instances and load balancers are billed per hour. You can also stop them between sessions (public IPs change on restart; run `terraform apply -refresh-only` to refresh the outputs).

## Tests
- **Base latency:** TCP connect, TTFB and total time, HTTP and HTTPS (each sample opens a new connection, so TTFB includes the TCP and TLS handshakes): `./scripts/measure.sh bogota <IP> <ISP> <fibra|movil> 100 2 [http|https]`.
- **Full app (ELB + EC2 + S3):** read and write 1 KB and 1 MB objects through the load balancer: `./scripts/measure.sh bogota-alb <ALB_DNS> <ISP> <fibra|movil> 100 2 http "/ping /api/read?obj=small /api/read?obj=large /api/write?obj=large"`. The CSV also records the time the app spent in S3 (`Server-Timing`).
- **App in Bogotá, data in Virginia:** `./scripts/measure_upstream.sh <BOGOTA_IP> <ISP> <fibra|movil>` makes N sequential calls from the Bogotá instance to the Virginia one over the private network (`enable_upstream_test`).
- **App in Bogotá, bucket in the parent region:** the Bogotá instance can also read and write the Virginia bucket (`&target=parent`). Run `EXTRA_QUERY=target=parent ./scripts/measure.sh bogota-parent-alb <BOGOTA_ALB_DNS> <ISP> <fibra|movil> 100 2 http "/api/read?obj=large /api/write?obj=large"`. Compare it with `bogota-alb` to see whether the cost comes from the Local Zone bucket or from the instance location.
- Use the labels `bogota`, `virginia`, `bogota-alb`, `virginia-alb`, `bogota-parent-alb`. The dashboard recognises them.

## Preliminary results
Median total time of the request through the load balancer, in milliseconds (Bogotá / Virginia), measured from Quito, Ecuador. ISP-A (fibre): three windows (Sunday afternoon, Monday 9:27 and Monday 12:15), 300 to 400 samples per series. ISP-B (mobile 5G): two windows (Monday 10:37 and Monday 12:55), 200 samples per series, plus a `/ping` check on Saturday with the same result.

![Bogotá vs Virginia, both operators](docs/img/resumen-bogota-vs-virginia.png)

| Test | ISP-A fibre | ISP-B mobile 5G |
|---|---|---|
| `/ping` | 47 / 224 | 348 / 280 |
| Read 1 MB from S3 | 110 / 261 | 415 / 324 |
| Write 1 MB to S3 | 251 / 302 | 534 / 354 |
| Write 1 MB, app in Bogotá + bucket in Virginia | 573 | 870 |
| Time spent in S3 inside the server, write 1 MB | 187 / 58 | 186 / 66 |

The result repeats in every window:

| Window | `/ping` | Read 1 MB | Write 1 MB |
|---|---|---|---|
| ISP-A, Sunday afternoon | 47 / 233 | 111 / 262 | 255 / 302 |
| ISP-A, Monday 9:27 | 46 / 218 | 111 / 254 | 251 / 291 |
| ISP-A, Monday 12:15 | 47 / 222 | 108 / 260 | 250 / 305 |
| ISP-B, Monday 10:37 | 327 / 261 | 385 / 299 | 505 / 329 |
| ISP-B, Monday 12:55 | 401 / 345 | 457 / 384 | 568 / 406 |

- With the app and its data together in Bogotá and a well-routed operator (ISP-A), Bogotá is faster: 79 % less network time, 58 % less to read 1 MB and 17 % less to write 1 MB. In the worst case (p95) writes are slower in Bogotá (393 ms against 342 ms).
- With ISP-B, Bogotá is slower in every test (24 % to 51 % in the combined medians, 16 % to 54 % per window). `mtr` shows why: the traffic of ISP-B toward the Bogotá Local Zone goes through Miami first (about 87 ms to reach Miami and 143 ms to reach Bogotá), while ISP-A reaches Bogotá directly in about 20 ms. It is that operator's route, not the zone.
- S3 inside the Local Zone is slower than regional S3 (writes: about 187 ms against 58 to 66 ms). It is the same with both operators, so it comes from the service and not from the user's network.
- Moving the app but leaving the data in the parent region makes writes 1.9 times (ISP-A) and 2.5 times (ISP-B) slower than keeping everything in Virginia. With ISP-B, 6 of 600 requests of that series took more than 1.5 s (the longest, 23 s), almost all of it inside the S3 call.
- Each query from the Bogotá instance to the Virginia instance over the private network cost about 59 ms (71 ms in the first test).
- Preliminary: one city, two operators, few windows. Do not generalize; measure from your own network.

## Route check (`mtr`)
![Traffic route to Bogotá and Virginia](docs/img/la-ruta-del-trafico.png)

Best round-trip time of 50 packets (`sudo mtr -rwbzc 50 <IP>`, files in `docs/mtr/`):

| Route | To the Bogotá Local Zone | To Virginia |
|---|---|---|
| ISP-A fibre (21 Nov) | 20 ms, direct | 95 ms, via Bogotá, Barranquilla and Miami |
| ISP-B mobile 5G (23 Nov) | 143 ms, via Miami | 117 ms, via Miami |

Cities are inferred from the host names that `mtr` shows, unanswered hops do not appear and routes change over time, so this is one observation per operator, not a rule.

## Dashboard
`dashboard.html` reads the CSVs in the browser (nothing is uploaded). Serve the folder (`python3 -m http.server`) and open `/dashboard.html`, or drag your CSVs onto the page. It shows p50/p95/p99, jitter, packet loss, time series and per-ISP comparison. To host it, use GitHub Pages or an S3 bucket behind CloudFront. `charts.html` renders the share cards of the images above (`?card=1|2|3&clean=1`).

## Good measurement practice
- Same client, same app, same instance type, same payload size; run both locations **in parallel**.
- Several windows (morning, afternoon, evening, business hours, weekend), at least 100 samples per route and ISP.
- Record ISP and network type honestly (`fibra` / `movil`). Mobile hotspots add radio latency to both targets.
- Results depend on ISP, city and hour. Do not generalize from one window.

## Limitations
- Local Zones have a limited service catalog and depend on the parent region (IAM, console).
- The Local Zone name and parent AZ can differ per account; check yours (`virginia_az` variable).
- The app reaches S3 through its public endpoints (no VPC gateway endpoint), the same way in both locations. A gateway endpoint could change the S3 numbers.
- Port 80 is open to the internet (mobile IPs change) and protected only by the token over plain HTTP. Fine for a short test; destroy afterwards.

## Contribute data
Open a PR adding your CSV to `data/community/` (see its README). Please include only data produced by `scripts/measure.sh`.

## License
MIT

# Nicoman Elevators: website

Static, mobile-first website for Nicoman Elevators (Port Blair, Andaman and Nicobar Islands).
Six pages, enquiry forms with WhatsApp fallback, and a scroll-driven elevator running through a hoistway in the background.

```
index.html             Home
installation.html      Elevator installation (+ installation enquiry form)
maintenance-amc.html   Maintenance & AMC (+ AMC enquiry form)
repair.html            Repair & servicing (+ repair request form)
about.html             About us
contact.html           Contact, map, general enquiry form
assets/css/style.css   Styles (palette and layout tokens at the top)
assets/js/main.js      Site details (SITE object), scroll elevator, forms
assets/img/            Photography and drawings used on the site
backend/lambda/        Enquiry endpoint that emails new enquiries via Amazon SES
robots.txt, sitemap.xml
```

## 1. Run locally

```bash
cd nicoman-elevators
python3 -m http.server 8080
# open http://localhost:8080
```

No build step. Edit the HTML, CSS or JS and refresh.

## 2. Before launch: fill in the placeholders

Search the site for the items below and replace them. Nothing here has been invented; each one needs the client's real information.

| Where | What to replace |
|---|---|
| `assets/js/main.js`, `SITE` object | Phone (`phoneDisplay` and `phoneTel`), WhatsApp number (`whatsappNumber`, digits with country code), email, office address, opening hours. Every phone, WhatsApp, email and address link on every page reads from here. |
| `contact.html`, map | The map is a search for "Port Blair". Replace it with the exact office location (Google Maps, Share, Embed a map). |
| `about.html`, "Our team" | Technician names, qualifications and certificates. Only publish verified credentials. Delete the placeholder box once filled. |
| `contact.html` and `index.html`, schema | Add `"telephone"` to the `LocalBusiness` JSON-LD once the number is confirmed. |
| Claims to confirm with the client | "AMC customers are first in line for breakdown calls" (`maintenance-amc.html`). Remove it if it is not the policy. Nicobar coverage line (`index.html`). IS 14665 reference (`installation.html`). Check with a qualified engineer or the inspectorate before launch. |
| Photography | The two images supplied are used as design imagery. The brief asks for genuine project photography. Replace them with the client's own installation photos when available, or confirm they are licensed for this use. |
| Testimonials and project portfolio | Not included at launch, per the brief's Phase 2. Add them when approved. |

## 3. Enquiry forms and email notifications

Forms work immediately: if no endpoint is set, a submitted enquiry opens WhatsApp with the details pre-filled. The site also includes:

- A honeypot field and a 2.5-second minimum fill time (silent bot filtering).
- Client-side mobile number validation, and server-side validation in the Lambda.

To email each enquiry to the business, deploy the Lambda:

1. **SES:** in the AWS region you choose (for example `ap-south-1`), verify the domain `nico.atla.in` (add the DKIM records in DNS). Request production access so mail can go to any address. Until then SES only sends to verified addresses.
2. **Lambda:** create a function, runtime Node.js 20 or 22, upload `backend/lambda/index.mjs` as `index.mjs`. Give it the IAM permission `ses:SendEmail`. Set environment variables:
   - `NOTIFY_TO`: comma-separated recipient addresses
   - `SES_FROM`: a verified sender, for example `enquiries@nico.atla.in`
   - `ALLOW_ORIGIN`: `https://nico.atla.in`
3. **API Gateway (HTTP API):** create a `POST /enquiry` route to the Lambda, enable CORS for the site origin, and copy the invoke URL.
4. Paste that URL into `SITE.formEndpoint` in `assets/js/main.js` and redeploy the site.

## 4. Hosting on AWS (nico.atla.in)

Recommended: a private S3 bucket behind CloudFront with HTTPS.

1. **S3:** create a bucket (block all public access on). Enable **versioning**, which gives file-level backups of every deploy.
2. **ACM:** request a certificate for `nico.atla.in` in **us-east-1** (N. Virginia), which CloudFront requires. Validate it via DNS.
3. **CloudFront:** create a distribution with the S3 bucket as origin, using Origin Access Control (OAC). Set the default root object to `index.html`, redirect HTTP to HTTPS, and add the alternate domain `nico.atla.in` with the certificate. Optionally add a response headers policy for security headers.
4. **DNS (wherever `atla.in` is managed):** add a CNAME `nico` pointing to the CloudFront domain name (for example `d123abc.cloudfront.net`).
5. **Deploy:**
   ```bash
   aws s3 sync . s3://YOUR-BUCKET --delete \
     --exclude ".git/*" --exclude "backend/*" --exclude "README.md"
   aws cloudfront create-invalidation --distribution-id YOUR-ID --paths "/*"
   ```
6. Optional: add AWS WAF on CloudFront for bot protection, and AWS Budgets for cost alerts.

## 5. Moving to the client's own domain later (GitHub Pages)

All links and images are relative, so the site works at any root or sub-path without changes. Before moving:

1. Point the repository's GitHub Pages source at the site folder (or move the contents to the repo root).
2. Set the custom domain in Pages, and create the DNS records GitHub specifies (CNAME to `<org>.github.io`).
3. Replace `https://nico.atla.in` with the new domain in every `<link rel="canonical">`, `og:` tag, `sitemap.xml` and `robots.txt`:
   ```bash
   grep -rl "nico.atla.in" . --exclude-dir=.git | xargs sed -i 's#https://nico.atla.in#https://NEW-DOMAIN#g'
   ```
4. Enforce HTTPS in Pages. Update the Lambda's `ALLOW_ORIGIN` to the new domain (if the form endpoint stays on AWS).
5. Keep the AWS stack running until DNS has moved, then retire the CloudFront distribution.

Note: GitHub Pages does not run the Lambda. The form endpoint can stay on AWS, with `SITE.formEndpoint` pointing at it.

## 6. Analytics, Search Console and Google Business Profile

- **Google Analytics 4:** add the measurement snippet to the `<head>` of every page, with the client's measurement ID.
- **Search Console:** verify `nico.atla.in` (DNS TXT record), then submit `sitemap.xml`.
- **Google Business Profile:** claim or create the listing for the Port Blair office, add the same phone, hours and address as the site, and link the website.

## 7. SEO notes

- Each page has a unique title, meta description, canonical URL and Open Graph tags.
- Target terms (installation, AMC, repair, and maintenance in Port Blair and Andaman) are used naturally in headings and body copy.
- Location claims are limited to the areas the brief says are served. Add more location pages only for areas the business genuinely covers.

## 8. Editing the content later

The site is plain HTML. Anyone comfortable with a text editor can change copy, and the shared details live in `SITE` in `assets/js/main.js`. If the client wants to edit pages in a visual CMS, the brief's preferred route is WordPress. That would mean rebuilding these pages as a theme; it is a separate piece of work.

## 9. Scope notes

- Phase 1 (launch) is complete: six core pages, enquiry forms, WhatsApp integration, mobile optimisation and basic SEO.
- Phase 2 (project portfolio, reviews, industry landing pages) and Phase 3 (CRM, service tickets, AMC renewal workflows) are not included.

# **<span style="color:#F38020;">Cloudflare Overview</span>**

**<span style="color:#F38020;">Cloudflare</span>** is a global network that provides security, performance, and reliability services to websites, APIs, and internet applications.

In the context of a **home lab**, <span style="color:#F38020;">Cloudflare</span> offers a variety of free tools, including:

- **<span style="color:#43A047;">DNS Management** – Host and manage your domain’s DNS records with fast propagation and built-in security.
- **<span style="color:#43A047;">DDoS Protection** – Protects your services from denial-of-service attacks.
- **<span style="color:#43A047;">Cloudflare Tunnels** (formerly *Argo Tunnel*) – Securely connect your local services to the internet without exposing your public IP.
- **<span style="color:#43A047;">Zero Trust Access** – Control and secure access to applications using identity-based authentication and policy enforcement.

---

### **Why Use Cloudflare Tunnel in a Home Lab?**

With **<span style="color:#FFB74D;">Cloudflare Tunnel**, you can securely expose your local services (such as Home Assistant, <span style="color:#00897B;">BookStack</span>, <span style="color:#009688;">Nextcloud</span>, etc.) to the internet:

- No need for **port forwarding**
- Your **public IP remains hidden**
- Encrypted connections from client to <span style="color:#F38020;">Cloudflare</span>’s network
- Works behind CGNAT or restrictive ISPs

---

**Example Use Case:**  
Run BookStack in your home lab and access it remotely via `https://wiki.example.com` through <span style="color:#FFB74D;">Cloudflare Tunnel</span>, without opening any ports on your firewall.

---

## **Create a Cloudflare Account**

1. Go to [https://dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up)  
2. Enter your **email address** and create a **password**.  
3. Click **Create Account**.  
4. Verify your email address by clicking the link sent to your inbox.

---

## **Add Your Domain and Transfer DNS to Cloudflare**

1. In the <span style="color:#F38020;">Cloudflare</span> dashboard, click **Onboard a domain**.

2. Enter your domain name (e.g., `example.com`) and click **Continue**.

3. Select the **Free Plan** (recommended for home lab use) or another plan if you need additional features.

4. <span style="color:#F38020;">Cloudflare</span> will automatically scan and import your existing DNS records:  
> * **Review the imported DNS records** carefully.
> * Ensure they match your current DNS provider's records.
> * Click **Continue to activation**

5. <span style="color:#F38020;">Cloudflare</span> will provide **two new nameservers** (e.g., `abby.ns.cloudflare.com` and `damon.ns.cloudflare.com`).

6. Log in to your **domain registrar** (e.g., Namecheap, GoDaddy, Google Domains).

7. Replace your registrar’s existing nameservers with the **Cloudflare-provided nameservers**.

8. Save the changes and allow up to 24 hours for DNS propagation (often completes in minutes).

⏱️ Once propagation is complete, <span style="color:#F38020;">Cloudflare</span> will manage your domain’s DNS and provide security and performance benefits.

!!! note
    You can skip step above if <span style="color:#F38020;">Cloudflare</span> is your domain registrar.



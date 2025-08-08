# **Cloudflare Overview**

**Cloudflare** is a global network that provides security, performance, and reliability services to websites, APIs, and internet applications.

In the context of a **home lab**, Cloudflare offers a variety of free tools, including:

- **DNS Management** – Host and manage your domain’s DNS records with fast propagation and built-in security.
- **DDoS Protection** – Protects your services from denial-of-service attacks.
- **Cloudflare Tunnels** (formerly *Argo Tunnel*) – Securely connect your local services to the internet without exposing your public IP.
- **Zero Trust Access** – Control and secure access to applications using identity-based authentication and policy enforcement.

---

### **Why Use Cloudflare Tunnel in a Home Lab?**

With **Cloudflare Tunnel**, you can securely expose your local services (such as Home Assistant, BookStack, Nextcloud, etc.) to the internet:

- No need for **port forwarding**
- Your **public IP remains hidden**
- Encrypted connections from client to Cloudflare’s network
- Works behind CGNAT or restrictive ISPs

---

**Example Use Case:**  
Run BookStack in your home lab and access it remotely via `https://wiki.example.com` through Cloudflare Tunnel, without opening any ports on your firewall.

---

## **Create a Cloudflare Account**

1. Go to [https://dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up)  
2. Enter your **email address** and create a **password**.  
3. Click **Create Account**.  
4. Verify your email address by clicking the link sent to your inbox.

---

## **Add Your Domain and Transfer DNS to Cloudflare**

1. In the Cloudflare dashboard, click **Onboard a domain**.

2. Enter your domain name (e.g., `example.com`) and click **Continue**.

3. Select the **Free Plan** (recommended for home lab use) or another plan if you need additional features.

4. Cloudflare will automatically scan and import your existing DNS records:  
* **Review the imported DNS records** carefully.
* Ensure they match your current DNS provider's records.
* Click **Continue to activation**

5. Cloudflare will provide **two new nameservers** (e.g., `abby.ns.cloudflare.com` and `damon.ns.cloudflare.com`).

6. Log in to your **domain registrar** (e.g., Namecheap, GoDaddy, Google Domains).

7. Replace your registrar’s existing nameservers with the **Cloudflare-provided nameservers**.

8. Save the changes and allow up to 24 hours for DNS propagation (often completes in minutes).

⏱️ Once propagation is complete, Cloudflare will manage your domain’s DNS and provide security and performance benefits.

!!! note
    You can skip step above if Cloudflare is your domain registrar.



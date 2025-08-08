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

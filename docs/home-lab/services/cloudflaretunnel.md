# **Setting Up Cloudflare Tunnel via Dashboard**

### **Prerequisites**
- A [Cloudflare account](https://dash.cloudflare.com/sign-up) 
- A domain name managed by Cloudflare DNS
- A home server or VM running your service

---
### **Steps**

1. **Log in to Cloudflare Dashboard:** [https://dash.cloudflare.com](https://dash.cloudflare.com)  
   Select your domain.

2. **Access Zero Trust:**  
> * Click **Zero Trust** in the left-hand menu.  
> * If this is your first time, set up a Zero Trust account (choose the **free plan** for home lab).

!!! note
    You will need to enter a payment method, but you will not be charged.

3. **Create a Tunnel:**  
> * In Zero Trust dashboard, go to **Networks → Tunnels**. 
> * Click **Create a tunnel**, then **Cloudflared** and give it a name (e.g., `HomeLabTunnel`).  
> * Click **Save tunnel**.

4. **Install and Run Cloudflared Connectors:**  
> * Choose your environment from the options provided (Windows, Mac, Debian, etc.) and select your system's architecture (64-bit or 32-bit).
> * Download the cloudflared installer from the link provided on the page or follow the instructions.
> * Run the installer on your home server or VM running your service.
> * Copy the **install token** from the text box on the page.
> * Run it on your server. This command includes a unique token that connects your server to the Cloudflare tunnel.

!!! warning "Store your token carefully!"
    The command you copy contains a sensitive token. Anyone with access to this token will be able to run the tunnel. Do not share it publicly.

---

### **Configure Public Hostnames**
1. Once your Cloudflared connector shows as **HEALTHY** in the dashboard, navigate to your newly created tunnel (e.g., `HomeLabTunnel`) and click **Configure**.

2. Go to the **Public hostnames** tab, click **Add a public hostname**.

3. Fill in the following details:
> * **Hostname:** Enter the subdomain or path you want to use (e.g., `wiki.example.com`)
> * **Service:** Select **HTTP** and enter the local URL of your service, including the port number (e.g., `http://192.168.1.100:8080`)

3. Click **Save**.
!!! note
    If your local application uses **HTTPS**, You will need to enable **No TLS Verify**. To do this, click on **Additional application settings**, then **TLS**, and toggle on**No TLS Verify**.

---

### **Test Access**
- Open a browser and go to your public hostname (e.g., `https://wiki.example.com`).
- Your traffic is now securely routed through Cloudflare without exposing your public IP or opening firewall ports.

---
📖 **Tip:** For enhanced security, consider enabling **Zero Trust Access** to add a layer of user authentication for your services.
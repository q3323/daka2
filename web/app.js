const siteConfig = {
  // 签名包准备好后填写，例如："./downloads/daka.hap"
  downloadUrl: "",
  icpNumber: "粤ICP备2026171342号-1"
};

const downloadButton = document.querySelector("#download-button");
const downloadLabel = document.querySelector("#download-label");
const icpLink = document.querySelector("#icp-link");

if (siteConfig.icpNumber) {
  icpLink.textContent = siteConfig.icpNumber;
}

if (siteConfig.downloadUrl) {
  downloadButton.href = siteConfig.downloadUrl;
  downloadButton.setAttribute("aria-disabled", "false");
  downloadButton.removeAttribute("tabindex");
  downloadLabel.textContent = "下载软件";
} else {
  downloadButton.href = "#";
  downloadButton.setAttribute("aria-disabled", "true");
  downloadButton.setAttribute("tabindex", "-1");
  downloadLabel.textContent = "安装包准备中";
}

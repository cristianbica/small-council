import { Controller } from "@hotwired/stimulus"

// const FRAME_ID = "page-modal"
// const REQUEST_HEADER = "X-Page-Modal-Request"
const PAGE_MODAL_SIZES = {
  fullscreen: "w-11/12 h-11/12 max-w-none"
}

export default class extends Controller {
  static targets = ["modalDialog"]

  connect() {
  }

  modalDialogTargetConnected(dialog) {
    const modalBox = dialog.querySelector(".modal-box")
    modalBox.className = "modal-box"
    if (modalBox && this.pageModalSize && PAGE_MODAL_SIZES[this.pageModalSize]) {
      const sizeClasses = PAGE_MODAL_SIZES[this.pageModalSize].split(" ")
      modalBox.classList.add(...sizeClasses)
    }
    dialog.showModal()
  }

  closeDialog(event) {
    this.modalDialogTarget.remove()
  }

  beforeTurboFrameLoad(event) {
    if(event.target.dataset.pageModalSize) {
      this.pageModalSize = event.target.dataset.pageModalSize;
    }
  }

  beforeFetchRequest(event) {
    debugger
    const frame = this.currentFrame()
    if (!frame) return
    if (!this.isModalRequest(event.target, frame)) return

    const headers = event.detail.fetchOptions.headers || {}
    headers[REQUEST_HEADER] = this.pendingRequestType || "inner"
    event.detail.fetchOptions.headers = headers

    this.pendingRequestType = null
  }


  // isModalRequest(target, frame) {
  //   if (!target) return false
  //   if (target === frame) return true
  //   if (typeof target.closest !== "function") return false

  //   return target.closest(`turbo-frame#${FRAME_ID}`) === frame
  // }
}

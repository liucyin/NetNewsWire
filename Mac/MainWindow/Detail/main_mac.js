function scrollDetection() {
	window.onscroll = function(event) {
		window.webkit.messageHandlers.windowDidScroll.postMessage(window.scrollY);
	}
}

function linkHover() {
	window.onmouseover = function(event) {
		var closestAnchor = event.target.closest('a')
		if (closestAnchor) {
			window.webkit.messageHandlers.mouseDidEnter.postMessage(closestAnchor.href);
		}
	}
	window.onmouseout = function(event) {
		var closestAnchor = event.target.closest('a')
		if (closestAnchor) {
			window.webkit.messageHandlers.mouseDidExit.postMessage(closestAnchor.href);
		}
	}
}

function imageViewer() {
	var container = document.getElementById('bodyContainer');
	if (!container) {
		return;
	}

	// Hover: pointing-hand cursor for clickable images (article body only)
	var images = container.querySelectorAll('img');
	for (var i = 0; i < images.length; i++) {
		images[i].style.cursor = 'pointer';
	}

	// Click: route image tap to native viewer
	container.addEventListener('click', function(event) {
		var img = event.target.closest('img');
		if (!img || !container.contains(img)) {
			return;
		}

		var src = img.currentSrc || img.src || img.getAttribute('data-src') || img.getAttribute('data-original');
		if (!src) {
			return;
		}

		event.preventDefault();
		event.stopPropagation();

		window.webkit.messageHandlers.openImageViewer.postMessage({src: src});
	}, true);
}

function postRenderProcessing() {
	scrollDetection();
	linkHover();
	imageViewer();
}

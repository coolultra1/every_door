window.onload = function() {
    const urlParams = new URLSearchParams(window.location.search);
    const code = urlParams.get('code');
    if(code) {
        window.opener.postMessage({ code: code }, '*');
        window.close();
    } else {
		alert('❌❌❌')
		window.location.href = '/';
	}
}

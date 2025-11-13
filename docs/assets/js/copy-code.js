document.addEventListener('DOMContentLoaded', function() {
  // Add click event to all pre elements for copying
  const preElements = document.querySelectorAll('.main-content pre');
  
  preElements.forEach(function(pre) {
    pre.addEventListener('click', function(e) {
      // Check if click is on the pseudo-element (copy button area)
      const rect = pre.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      
      // Copy button is in top-right corner
      if (x > rect.width - 80 && y < 30) {
        const code = pre.querySelector('code');
        const text = code ? code.textContent : pre.textContent;
        
        navigator.clipboard.writeText(text).then(function() {
          // Change button text temporarily
          const originalContent = pre.getAttribute('data-copy-text') || 'Copy';
          pre.style.setProperty('--copy-text', '"Copied!"');
          
          setTimeout(function() {
            pre.style.setProperty('--copy-text', '"' + originalContent + '"');
          }, 2000);
        }).catch(function(err) {
          console.error('Failed to copy:', err);
        });
      }
    });
    
    // Change cursor to pointer when hovering over copy button area
    pre.addEventListener('mousemove', function(e) {
      const rect = pre.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      
      if (x > rect.width - 80 && y < 30) {
        pre.style.cursor = 'pointer';
      } else {
        pre.style.cursor = 'default';
      }
    });
  });
});


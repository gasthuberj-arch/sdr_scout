function initQuiz() {
  // Find all quiz units (either individual .quiz-container, or .quiz-question blocks)
  const containers = document.querySelectorAll('.quiz-container');

  containers.forEach(function(container) {
    const questions = container.querySelectorAll('.quiz-question');

    // If container holds multiple questions, initialize each independently
    if (questions.length > 1) {
      questions.forEach(function(q) {
        setupQuizUnit(q, q);
      });
    } else {
      setupQuizUnit(container, container);
    }
  });

  function setupQuizUnit(rootEl, searchScope) {
    const options = searchScope.querySelectorAll('.quiz-option');
    if (options.length === 0) return;

    let explanation = searchScope.querySelector('.quiz-explanation, .quiz-feedback');

    // Create explanation container if missing
    if (!explanation) {
      explanation = document.createElement('div');
      explanation.className = 'quiz-explanation';
      searchScope.appendChild(explanation);
    }

    options.forEach(function(opt) {
      opt.addEventListener('click', function() {
        const isCorrect = opt.dataset.correct === 'true';

        // Clear previous state on options
        options.forEach(function(o) {
          o.classList.remove('correct', 'incorrect');
        });

        if (isCorrect) {
          opt.classList.add('correct');
          explanation.style.backgroundColor = '#e8f5e9';
          explanation.style.border = '1px solid #a5d6a7';
          explanation.style.color = '#1b5e20';
          if (!explanation.dataset.customText) {
            explanation.innerHTML = '<strong>Correct!</strong> ' + (explanation.dataset.correctText || 'Well done!');
          }
        } else {
          opt.classList.add('incorrect');
          explanation.style.backgroundColor = '#ffebee';
          explanation.style.border = '1px solid #ef9a9a';
          explanation.style.color = '#b71c1c';

          // Highlight the correct one
          options.forEach(function(o) {
            if (o.dataset.correct === 'true') {
              o.classList.add('correct');
            }
          });

          if (!explanation.dataset.customText) {
            explanation.innerHTML = '<strong>Incorrect.</strong> ' + (explanation.dataset.incorrectText || 'Check the highlighted correct answer.');
          }
        }

        explanation.style.display = 'block';
      });
    });
  }
}

document.addEventListener('DOMContentLoaded', initQuiz);

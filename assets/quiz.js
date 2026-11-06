function initQuiz() {
  document.querySelectorAll('.quiz-container').forEach(function(quiz) {
    const options = quiz.querySelectorAll('.quiz-option');
    const explanation = quiz.querySelector('.quiz-explanation');

    options.forEach(function(opt) {
      opt.addEventListener('click', function() {
        if (quiz.dataset.answered === 'true') return;
        quiz.dataset.answered = 'true';

        const isCorrect = opt.dataset.correct === 'true';
        if (isCorrect) {
          opt.classList.add('correct');
          explanation.style.backgroundColor = '#e8f5e9';
          explanation.style.border = '1px solid #a5d6a7';
          explanation.style.color = '#1b5e20';
        } else {
          opt.classList.add('incorrect');
          explanation.style.backgroundColor = '#ffebee';
          explanation.style.border = '1px solid #ef9a9a';
          explanation.style.color = '#b71c1c';
          
          // also highlight the correct one
          options.forEach(function(o) {
            if (o.dataset.correct === 'true') {
              o.classList.add('correct');
            }
          });
        }
        explanation.style.display = 'block';
      });
    });
  });
}

document.addEventListener('DOMContentLoaded', initQuiz);

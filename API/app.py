from flask import Flask, request, jsonify
import os
import tensorflow.lite as tflite
import numpy as np
from PIL import Image
from collections import Counter

app = Flask(__name__)

# Define class labels
CLASS_LABELS = ['Adenocarcinoma', 'Benign', 'Squamous Cell Carcinoma']

# Load all three TFLite models
MODEL_PATHS = {
    "model1": r"D:\MAD\MINI\cancervision\api\lung_cancer_mobilenet.tflite",
    "model2": r"D:\MAD\MINI\cancervision\api\lung_cancer_resnet.tflite",
    "model3": r"D:\MAD\MINI\cancervision\api\lung_cancer_vgg19.tflite",
}

# Ensure models exist
for model_name, path in MODEL_PATHS.items():
    if not os.path.exists(path):
        raise FileNotFoundError(f"Model file not found at: {path}")

# Load interpreters for each model
interpreters = {}
for model_name, path in MODEL_PATHS.items():
    interpreter = tflite.Interpreter(model_path=path)
    interpreter.allocate_tensors()
    interpreters[model_name] = interpreter
    print(f" Loaded model: {model_name} from {path}")

@app.route("/")  # Homepage
def home():
    return "Cancer Detection API is Running!"

@app.route("/predict", methods=["POST"])
def predict():
    try:
        if "file" not in request.files:
            print(" No file provided in request")
            return jsonify({"error": "No file provided"}), 400

        file = request.files["file"]
        print(f" Received file: {file.filename}")

        image = Image.open(file).resize((150, 150))  # Resize to model input size
        image = np.array(image, dtype=np.float32) / 255.0
        image = np.expand_dims(image, axis=0)  # Add batch dimension

        predictions = []
        confidence_scores = []
        model_predictions = []

        # Loop through each model and get predictions
        for model_name, interpreter in interpreters.items():
            print(f" Processing image with {model_name}")
            
            input_details = interpreter.get_input_details()
            output_details = interpreter.get_output_details()

            interpreter.set_tensor(input_details[0]["index"], image)
            interpreter.invoke()

            raw_output = interpreter.get_tensor(output_details[0]["index"])
            raw_output = np.squeeze(raw_output)  # Remove batch dimension

            predicted_class = int(np.argmax(raw_output))
            confidence_score = float(np.max(raw_output))

            predictions.append(predicted_class)
            confidence_scores.append(confidence_score)

            model_predictions.append({
                "model": model_name,
                "predicted_class": CLASS_LABELS[predicted_class],
                "confidence": confidence_score
            })

            print(f" {model_name} predicted: {CLASS_LABELS[predicted_class]} with confidence {confidence_score:.2f}")

        # Perform Majority Voting
        class_votes = Counter(predictions)
        final_class = class_votes.most_common(1)[0][0]  # Get the most voted class

        # Compute final confidence as the average confidence of models that predicted the final class
        relevant_confidences = [conf for i, conf in enumerate(confidence_scores) if predictions[i] == final_class]
        final_confidence = float(np.mean(relevant_confidences))

        final_prediction = {
            "final_predicted_class": CLASS_LABELS[final_class],
            "final_confidence": final_confidence
        }

        print(f" Final Prediction: {CLASS_LABELS[final_class]} with confidence {final_confidence:.2f}")

        return jsonify({
            "individual_model_predictions": model_predictions,
            "final_prediction": final_prediction
        })

    except Exception as e:
        print(f" Error: {e}")
        return jsonify({"error": str(e)}), 500
    
if __name__ == "__main__":
    print("Starting Cancer Detection API...")
    app.run(host="0.0.0.0", port=5000, debug=True)
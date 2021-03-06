//
//  MicViewController.swift
//  Motif
//
//  Created by Michael Asper on 3/7/18.
//  Copyright © 2018 Motif. All rights reserved.
//

import UIKit
import Firebase
import FirebaseStorage
import AudioKit
import AudioKitUI
import CoreData

class MicViewController: UIViewController {

    @IBOutlet weak var timerLabel: UILabel!
    @IBOutlet weak var circleButtonView: CircleBackgroundView!
    @IBOutlet var backgroundView: RadialGradientView!
    @IBOutlet weak var checkButton: UIButton!
    @IBOutlet weak var trashButton: UIButton!
    @IBOutlet weak var inputWave: EZAudioPlot!
    
    lazy var storage = Storage.storage()
    
    
    @IBAction func startRecording() {
        isRecording = !isRecording
        
        if isRecording {
            start()
        } else {
            stop()
        }
    }
    
    @IBAction func trashRecording() {
        let refreshAlert = UIAlertController(title: "Delete?", message: "All data will be lost.", preferredStyle: UIAlertControllerStyle.alert)
        
        refreshAlert.addAction(UIAlertAction(title: "Delete", style: .default, handler: { (action: UIAlertAction!) in
            self.resetUI()
            print("Thing is deleted")
        }))
        
        refreshAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction!) in
            print("Cancelled")
        }))
        
        present(refreshAlert, animated: true, completion: nil)
    }
    
    @IBAction func keepRecording() {
        let alert = UIAlertController(title: "Keep Recording", message: "Label recording", preferredStyle: .alert)
        
        alert.addTextField { (textField) in
            textField.placeholder = "My Song Name"
        }
        
        alert.addTextField { (textField) in
            textField.placeholder = "tag1, tag2,..."
        }
        
        
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] (_) in
            let textField = alert?.textFields![0]
            if let songName = textField?.text {
                
                
                AudioManager.sharedInstance.saveSong(fileName: songName.replace(target: " ", withString: "_"), mode: .microphone) { result, url, duration in
                    if result {
                        print(duration)
                        //let localFile = URL(string: url)!
                        DispatchQueue.main.async {
                            // Cloud upload
                            let uid = Auth.auth().currentUser!.uid
                            let clipRef = self.storage.reference().child(uid).child(songName)
                            clipRef.putFile(from: url, metadata: nil) { metadata, error in
                                if let error = error {
                                    // Uh-oh, an error occurred!
                                    print("Error uploading: \(error)")
                                    return
                                }
                                self.uploadSuccess(clipRef, storagePath: clipRef.fullPath, songName: "Motif-\(songName)", duration: duration)
                            }
                        }
                    } else {
                        print("failed")
                    }
                    
                    AudioManager.sharedInstance.resetRecording()

                }
            } else {
                print("Failed")
            }
            self.resetUI()
            
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction!) in
            
            print("Cancelled")
        }))
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func uploadSuccess(_ storageRef: StorageReference, storagePath: String, songName: String, duration: Double) {
        print("Upload Succeeded!")
        storageRef.downloadURL { (url, error) in
            if let error = error {
                print("Error getting download URL: \(error)")
                return
            }
            print("Absolute url")
            print(url?.absoluteString ?? "")
            self.saveSong(name: songName, location: url!, duration: duration, storagePath: storagePath)
            //UserDefaults.standard.set(storagePath, forKey: "storagePath")
            //UserDefaults.standard.synchronize()
        }
    }
    
    var AudioManagerInstance = AudioManager.sharedInstance
    
    var plot: AKNodeOutputPlot!
    
    var isRecording = false
    var musicTimer: Timer!
    var time: Double = 0
    var startTime: Double = 0
    var endTime: Double = 0
    
    var db: Firestore!
    var audioClipsCollection: CollectionReference!
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent // .default
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        trashButton.isHidden = true
        checkButton.isHidden = true
        
        db = Firestore.firestore()
        let uid = Auth.auth().currentUser?.uid ?? "0"
        audioClipsCollection = db.collection("users").document(uid).collection("audio_clips")
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        let color1 = UIColor(red: 0.00, green: 0.27, blue: 0.77, alpha: 0.7)
        let color2 = UIColor(red: 0.00, green: 0.27, blue: 0.77, alpha: 0.0)
        backgroundView.colors = [color1, color2]
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        setupPlot()
    }
    
    func saveSong(name: String, location: URL, duration: Double, storagePath: String) {
            
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let context = appDelegate.persistentContainer.viewContext
        
        let song = NSEntityDescription.insertNewObject(forEntityName: "Song",
                                                       into: context)
        song.setValue(name, forKey: "name")
        song.setValue(location, forKey: "url")
        song.setValue(duration, forKey: "duration")
        song.setValue(storagePath, forKey: "storageRef")
        
        
        do {
            try context.save()
        } catch {
            // If an error occurs
            let nserror = error as NSError
            NSLog("Unresolved error \(nserror), \(nserror.userInfo)")
            abort()
        }
        let newClipRef = audioClipsCollection.document(name)
        newClipRef.setData([
            "name": name,
            "duration": duration,
            "storageRef": storagePath]) {err in
                if let err = err {
                    print("Error updating document: \(err)")
                } else {
                    print("Document successfully updated")
                }
        }
        
    }

    @objc func updateTimer() {
        
        // Calculate total time since timer started in seconds
        time = Date().timeIntervalSinceReferenceDate - startTime
        
        // Calculate minutes
        let minutes = UInt8(time / 60.0)
        time -= (TimeInterval(minutes) * 60)
        
        // Calculate seconds
        let seconds = UInt8(time)
        time -= TimeInterval(seconds)
    
        
        // Format time vars with leading zero
        let strMinutes = String(format: "%01d", minutes)
        let strSeconds = String(format: "%02d", seconds)
        
        timerLabel.text = "\(strMinutes):\(strSeconds)"
    }
    
    func start() {
        
        // Reset timer for new recording
        timerLabel.text = "0:00"
        
        // Set up plot for recording
        plot.color = .red
        plot.resetHistoryBuffers()
        plot.resume()


        startTime = Date().timeIntervalSinceReferenceDate
        musicTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateTimer), userInfo: nil, repeats: true)
        
        AudioManagerInstance.startRecording()
        //plot.node = AudioManagerInstance.getMic()
        
        setUpRecordingUI()
        
    }
    
    func stop() {
        
        // Stop Timing
        musicTimer.invalidate()
        
        // Stop tracking
        plot.color = .blue
        plot.pause()
        
        // Keep file in memory for additional processing
        AudioManagerInstance.stopRecording()
        
        setUpPostRecordingUI()
    }
    
    func setupPlot() {
        plot = AKNodeOutputPlot( AudioManagerInstance.getMic(), frame: inputWave.bounds)
        plot.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
        plot.plotType = .rolling
        plot.shouldFill = true
        plot.shouldMirror = true
        plot.color = .blue
        plot.gain = 3
        plot.pause()
        inputWave.addSubview(plot)
    }
   
    func setUpPostRecordingUI() {
        UIView.animate(withDuration: 0.25, animations: {
            self.trashButton.isHidden = false
            self.checkButton.isHidden = false
           
            let color1 = UIColor(red: 0.00, green: 0.27, blue: 0.77, alpha: 0.7)
            let color2 = UIColor(red: 0.00, green: 0.27, blue: 0.77, alpha: 0.0)
            self.backgroundView.colors = [color1, color2]
            self.circleButtonView.backgroundColor = UIColor(red: 0.33, green: 0.64, blue: 0.95, alpha: 1.0)
            self.circleButtonView.layer.cornerRadius = self.circleButtonView.bounds.size.width / 2
            self.circleButtonView.transform = CGAffineTransform.identity
        })
    }
    
    func setUpRecordingUI() {
        UIView.animate(withDuration: 0.25, animations: {
            self.trashButton.isHidden = true
            self.checkButton.isHidden = true
            self.inputWave.isHidden = false
            let color1 = UIColor(red: 1, green: 0, blue: 0, alpha: 0.7)
            let color2 = UIColor(red: 1, green: 0, blue: 0, alpha: 0.0)
            self.backgroundView.colors = [color1, color2]
            self.circleButtonView.backgroundColor = .red
            self.circleButtonView.layer.cornerRadius = 10
            self.circleButtonView.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        })
    }
    
    func resetUI() {
       
        UIView.animate(withDuration: 0.25, animations: {
            self.trashButton.isHidden = true
            self.checkButton.isHidden = true
            self.inputWave.isHidden = true
            self.timerLabel.text = "0:00"
            self.plot.clear()
        })
    }
}

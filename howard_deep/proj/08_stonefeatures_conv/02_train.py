#!/usr/bin/env python

# /********************************************************************
# Filename: train.py
# Author: AHN
# Creation Date: Sep 9, 2017
# **********************************************************************/
#
# Build and train stonefeatures_conv model
#

from __future__ import division, print_function
from pdb import set_trace as BP
import inspect
import os,sys,re,json,shutil
import numpy as np
import scipy
from numpy.random import random
import argparse
import matplotlib as mpl
mpl.use('Agg') # This makes matplotlib work without a display
from matplotlib import pyplot as plt
import keras.layers as kl
import keras.models as km
import keras.optimizers as kopt
import keras.activations as ka

# Look for modules in our pylib folder
SCRIPTPATH = os.path.dirname(os.path.realpath(__file__))
sys.path.append(re.sub(r'/proj/.*',r'/pylib', SCRIPTPATH))
import ahnutil as ut

BATCH_SIZE=32
GRIDSIZE=5
RESOLUTION=80
MODELFILE='model.h5'
WEIGHTSFILE='weights.h5'

#---------------------------
def usage(printmsg=False):
    name = os.path.basename(__file__)
    msg = '''
    Name:
      %s --  Build and train stonefeatures model
    Synopsis:
      %s --epochs <n> --rate <learning_rate>
      or
      %s --visualize
    Description:
      Try to train and visualize a feature map for black and white stones.
    Example:
      %s --epochs 10 --rate 0.001
    ''' % (name,name,name,name)
    if printmsg:
        print(msg)
        exit(1)
    else:
        return msg


#-----------------
class MapModel:
    #----------------------------------------------
    def __init__(self,resolution,gridsize,rate=0):
        self.resolution = resolution
        self.gridsize = gridsize
        self.rate = rate
        self.build_model()

    #-----------------------
    def build_model(self):
        # VGG style convolutional model
        inputs = kl.Input(shape=(1,self.resolution,self.resolution))
        x = kl.Conv2D(32,(3,3), activation='selu')(inputs)
        x = kl.Conv2D(32,(3,3), activation='selu')(x)
        #x_flat0 = kl.Flatten()(x)
        x = kl.MaxPooling2D()(x)
        x_flat1  = kl.Flatten()(x)
        # Dense layer used for localization
        x_circle = kl.Dense(3, name='circle')(x_flat1)
        x = kl.Conv2D(64,(3,3), activation='selu')(x)
        x = kl.Conv2D(64,(3,3), activation='selu')(x)
        x = kl.MaxPooling2D()(x)
        # Conv layer used for classification
        x_class_conv = kl.Conv2D(2,(3,3),name='classconv')(x)
        x_class_pool = kl.GlobalAveragePooling2D()(x_class_conv)
        x_class = kl.Activation('softmax', name='class')(x_class_pool)
        #x_class  = kl.Dense(2,activation='softmax', name='class')(x_flat0)
        self.model = km.Model(inputs=inputs, outputs=[x_class,x_circle])
        self.model.summary()
        if self.rate > 0:
            opt = kopt.Adam(self.rate)
        else:
            opt = kopt.Adam()
        self.model.compile(loss=['categorical_crossentropy','mse'], optimizer=opt,
                           metrics=['accuracy'], loss_weights=[1.,1.])

    #------------------------------------------------------------------------------------------
    def train(self,train_input, train_output, valid_input, valid_output, batch_size, epochs):
        print("fitting model...")
        self.model.fit(train_input, train_output,
                        validation_data=(valid_input, valid_output),
                        batch_size=batch_size, epochs=epochs)

    #---------------------------------------------------
    def print_results(self, valid_input, valid_output):
        preds = self.model.predict(valid_input, batch_size=32)
        classpreds = preds[0]
        pospreds = preds[1]
        valid_output_class = valid_output[0]
        valid_output_xyr   = valid_output[1]
        for i,cp in enumerate(classpreds):
            pp = pospreds[i]
            tstr = 'class: %s pred: %s center: %.1f %.1f pred: %.1f %.1f' \
            %  ('b' if valid_output_class[i][1] else 'w',
                'b' if cp[1]>cp[0] else 'w',
                valid_output_xyr[i][0], valid_output_xyr[i][1],
                pp[0], pp[1])
            print(tstr)

# Dump the top conv layer results for black and white to viz_<n>.jpg
# for the the first couple images in data
#---------------------------------------------------------------------
def visualize(model, layer_name, data, filenames):
    BLACK=1
    WHITE=0
    intermediate_layer_model = km.Model(inputs=model.model.input,
                                        outputs=model.model.get_layer(layer_name).output)
    intermediate_output = intermediate_layer_model.predict(data)

    for img_num in range(5):
        conv_w = intermediate_output[img_num][WHITE]
        img_w = scipy.misc.imresize(conv_w, (80,80), interp='nearest')
        conv_b = intermediate_output[img_num][BLACK]
        img_b = scipy.misc.imresize(conv_b, (80,80), interp='nearest')

        plt.figure()
        plt.subplot(141)
        orig = data[img_num][0].astype(np.uint8)
        # Input image
        plt.imshow(orig,cmap='Greys')
        plt.subplot(142)
        # White convolution layer
        plt.imshow(img_w, cmap='Greys', alpha=1.0)
        plt.subplot(143)
        # Black convolution layer
        plt.imshow(img_b, cmap='Greys', alpha=1.0)
        plt.subplot(144)
        # Overlay black conv layer on original
        plt.imshow(orig, cmap='Greys', alpha=1.0)
        plt.imshow(img_b, cmap='cool', alpha=0.5)
        # Save
        plt.savefig('viz_%d.jpg' % img_num)


#-----------
def main():
    if len(sys.argv) == 1:
        usage(True)

    parser = argparse.ArgumentParser(usage=usage())
    parser.add_argument("--epochs", required=False, default=10, type=int)
    parser.add_argument("--rate", required=False, default=0, type=float)
    parser.add_argument("--visualize", required=False, action='store_true')
    args = parser.parse_args()
    model = MapModel(RESOLUTION, GRIDSIZE, args.rate)
    if args.visualize:
        if os.path.exists(WEIGHTSFILE):
            print('Loading weights from file %s...' % WEIGHTSFILE)
            model.model.load_weights(WEIGHTSFILE)
    else:
        if os.path.exists(MODELFILE):
            print('Loading model from file %s...' % MODELFILE)
            model.model = km.load_model(MODELFILE)
            if args.rate:
                model.model.optimizer.lr.set_value(args.rate)

    print('Reading data...')
    images = ut.get_data(SCRIPTPATH, (RESOLUTION,RESOLUTION))
    meta = ut.get_meta(SCRIPTPATH)
    output_class = ut.get_output_by_key(SCRIPTPATH,'class')
    output_xyr   = ut.get_output_by_key(SCRIPTPATH,'xyr')
    # Normalize training and validation data by train data mean and std
    means,stds = ut.get_means_and_stds(images['train_data'])
    ut.normalize(images['train_data'],means,stds)
    ut.normalize(images['valid_data'],means,stds)

    train_output_class = ut.onehot(output_class['train_output'])
    train_output_xyr   = output_xyr['train_output']
    valid_output_class = ut.onehot(output_class['valid_output'])
    valid_output_xyr   = output_xyr['valid_output']

    if args.visualize:
        print('Dumping conv layer images to jpg')
        visualize(model, 'classconv', images['train_data'], ['train/' + x for x in meta['train_filenames']])
        exit(0)

    # Train
    print('Start training...')
    model.train(images['train_data'], [train_output_class, train_output_xyr],
               images['valid_data'], [valid_output_class, valid_output_xyr],
               BATCH_SIZE, args.epochs)
    model.model.save_weights(WEIGHTSFILE)
    model.model.save(MODELFILE)
    model.print_results(images['valid_data'], [valid_output_class, valid_output_xyr])

if __name__ == '__main__':
    main()
